(ns spiralweb.core
  (:require [clojure.string :refer [starts-with? trim index-of]]
            [clojure.tools.cli :refer [parse-opts]]
            [taoensso.timbre :as t :refer [debug error]]
            [edessa.parser :refer :all]))

; Spiralweb language definition

(def non-breaking-ws
  (parser (one-of [\space \tab])
          :name "Non-breaking whitespace"))
(def nl
  (parser (match \newline)
          :name "Newline"
          :using (fn [x] {:type :newline :value (str \newline)})))

(def t-text
    (parser
     (plus
        (parser (not-one-of [\@ \[ \] \= \, \newline])
                :name"Non-Reserved Characters") )
     :using (fn [x] {:type :text :value (apply str x)})
     :name "Text Token"))

(def code-end
  (parser (literal "@end")
          :using (fn [_] {:type :code-end :value "@end"})
          :name "Code End" ))

(def doc-directive
  (parser (literal "@doc")
          :using (fn [_] {:type :doc-directive :value "@doc"})))

(def code-directive
  (parser (literal "@code")
          :using (fn [_] {:type :code-directive :value "@code"})))

(def at-directive
  (parser (literal "@@")
         :using (fn [_] {:type :at-directive :value "@@"})))

(def comma
  (parser (match \,)
          :using (fn [_] {:type :comma :value ","})))

(def t-equals
  (parser (match \=)
          :using (fn [_] {:type :equals :value "="})))

(def open-proplist
  (parser (match \[)
         :using (fn [_] {:type :open-proplist :value "["})))

(def close-proplist
  (parser (match \])
          :using (fn [_] {:type :close-proplist :value "]"})))

(def chunkref
  (parser
     (then
      (star non-breaking-ws)
      (match \@) (match \<)
      (plus (not-one-of [\> \newline]))
      (match \>)
      (star non-breaking-ws))
     :using
     (fn [x]
       (let [ref-text (apply str x)
             trimmed-ref-text (trim ref-text)]
         {:type :chunk-reference
          :name (subs trimmed-ref-text 2 (- (count trimmed-ref-text) 1))
          :indent-level (index-of ref-text "@<")}))
    :name "Chunk Reference"))

(def docline
  (parser
    (choice t-text
            nl
            at-directive
            comma
            t-equals
            open-proplist
            close-proplist)
    :name "Docline"))

(def codeline
  (parser
    (choice t-text
            nl
            at-directive
            comma
            t-equals
            open-proplist
            close-proplist
            chunkref)
    :name "Codeline"))

(def doclines (plus docline))

(def property
  (parser (then t-text t-equals t-text)
         :using
         (fn [x]
           (let [scrubbed (filter (comp not nil?) x)]
             {:type :property :value {:name (-> scrubbed first :value trim)
                                      :value (-> scrubbed (nth 2) :value trim)}}))))

(def property-sequence (choice (then comma property) property))

(def property-list
  (parser (then open-proplist (star property-sequence) close-proplist (star non-breaking-ws))
          :using
         (fn [x]
           {:type :properties :value
            (filter (fn [y] (and (not (nil? y))
                                 (= :property (:type y)))) x)})))

(defn- prop-token? [t] (= :properties (:type t)))

(def doc-definition
  (parser (then doc-directive t-text (optional property-list) nl doclines)
          :using
         (fn [x]
           (let [[_ n & lines :as all-tokens] (filter (comp not nil?) x)
                 props (flatten (map :value (filter prop-token? all-tokens)))]
             {:type :doc :options props
              :name (-> n :value trim) :lines (filter (comp not prop-token?) lines)}))))

(defn code-end? [t] (= (:type t) :code-end))

(def code-definition
  (parser (then code-directive t-text (optional property-list) nl (plus codeline) code-end)
          :using
         (fn [x]
           (let [[_ n & lines :as all-tokens] (filter (comp not nil?) x)
                 props (flatten (map :value (filter prop-token? all-tokens)))]
             {:type :code :options props
              :name (-> n :value trim) :lines (filter #(not (or (prop-token? %) (code-end? %))) lines)}))))

(def web (star (choice code-definition doc-definition doclines)))

; CLI interface

(t/merge-config! {:level :error})

(defn is-code-chunk? [c]
  (= (:type c) :code))

(defn combine-code-chunks [result chunks]
  (let [chunk (first chunks)]
    (cond
      (empty? chunks)
      result
      (not (is-code-chunk? chunk))
      (recur result (rest chunks))
      (contains? result (:name chunk))
      (recur
       (update-in result [(:name chunk) :lines]
                  (fn [x] (concat (:lines chunk) x)))
       (rest chunks))
      :else
      (recur (assoc result (:name chunk) chunk)
             (rest chunks)))))

(defn output-option? [opt]
  (= "out" (-> opt :value :name)))

(defn output-path [c]
  (->
   (filter output-option? (:options c))
   first
   :value
   :value))

(defn has-output-path?
  "Examines a chunk map and indicates whether there is an output path specified on the chunk."
  [c]
  (some? (output-path c)))

(defn is-chunk-reference? [c]
  (= :chunk-reference (:type c)))

(defn build-chunk-crossrefs
  "Accepts a sequence of chunks, some of which may be documentation chunks 
  and some of which may be code chunks, and builds a map of maps indicating
  whether one chunk refers to another.

  {\"asdf\" : {\"def\": true, \"abc\": false }}

  This map is not sparse. It will include some entry for each chunk in the original list."
  [chunks]
  (letfn [(add-references [chunk result]
            (let [ref-lines (filter is-chunk-reference? (:lines chunk))
                  chunk-adjacent (get result (:name chunk))
                  additions (interleave (map :name ref-lines) (repeat true))]
              (if (empty? additions)
                result
                (assoc result (:name chunk)
                       (apply (partial assoc chunk-adjacent) additions)))))

          (build-chunk-crossrefs-inner [chunks result]
            (let [[c & cs] chunks]
              (cond
                (empty? chunks) result
                :else (recur cs (add-references c result)))))]

    (build-chunk-crossrefs-inner chunks (apply (partial assoc {})
                                               (interleave (map :name (filter is-code-chunk? chunks)) (repeat {}))))))

; Let's take a step back and think about tangling. We want to take the input
; text and parse it. If there is an error, we stop and report the error.
; If not, we want to expand the code chunks out. Finally, we want to output
; chunks. If a user passes in a specific chunk or set of chunks, we dump those
; out. Otherwise, we want to find all those chunks with output paths and write
; them out.

(defn topologically-sort-chunks
  "Accepts a map of code chunks (name -> value) and produces a topologically sorted list of chunk IDs."
  [chunks]
  (let [has-incoming-edges? (fn [xrefs cn]
                              (some #(some? (get % cn)) (vals xrefs)))

        find-candidate-nodes (fn [xrefs]
                               (filter (comp not (partial has-incoming-edges? xrefs)) (keys xrefs)))

        ts-inner (fn [res xrefs]
                   (let [candidates (find-candidate-nodes xrefs)]
                     (if (empty? candidates) [res xrefs]
                         (recur (cons (first candidates) res)
                                (dissoc xrefs (first candidates))))))
        xrefs (build-chunk-crossrefs (vals chunks))
        [sorted-names leftovers] (ts-inner [] xrefs)]
    (if (empty? leftovers)
      sorted-names
      "ERROR! Circular reference.")))

(defn expand-refs [chunk all-chunks]
  (letfn [(expand-refs-inner [lines all-chunks result]
            (let [line (first lines)]
              (cond
                (empty? lines) result
                (is-chunk-reference? line)
                (recur (rest lines) all-chunks
                       (concat (-> all-chunks (get (:name line)) :lines) result))
                :else (recur (rest lines) all-chunks (cons line result)))))]

    (assoc chunk :lines
           (expand-refs-inner (:lines chunk) all-chunks []))))

(defn expand-chunks [queue chunks]
  (if (empty? queue)
    chunks
    (recur (rest queue)
           (assoc chunks (first queue)
                  (expand-refs (get chunks (first queue)) chunks)))))

(defn expand-code-refs
  "Accepts a map of chunks (the key being the name of the chunk, value being the unique value."
  [chunks]
  (let [chunk-seq (topologically-sort-chunks chunks)]
    (expand-chunks chunk-seq chunks)))

(defn refine-code-chunks [text]
  (let [parse-tree (apply-parser web text)]
    (if (or (failure? parse-tree)
            (input-remaining? parse-tree))
      nil
      (->> parse-tree
           result
           first
           (filter is-code-chunk?)
           (combine-code-chunks {})
           expand-code-refs))))

(defn chunk-content [c]
  (->> c :lines (map :value) (apply str)))

(defn output-code-chunks [chunks]
  (doseq [chunk chunks]
    (if (has-output-path? chunk)
      (spit (output-path chunk) (chunk-content chunk))
      (println (chunk-content chunk)))))

(defn tangle-text [txt output-chunks]
  (let [chunks (refine-code-chunks txt)]
    (output-code-chunks
     (cond
       (not (empty? output-chunks))
       (filter (fn [x]
                 (contains? (set output-chunks) (:name x)))
               (vals chunks))
       (contains? chunks "*")
       (list (get chunks "*"))
       :else
       (filter has-output-path? (vals chunks))))))

(defn tangle
  "Accepts a list of files, extracts code and writes it out."
  ([files output-chunks]
   (doseq [f files]
     ; TODO: error handling
     (tangle-text (slurp f) output-chunks)))
  ([files] (tangle files nil)))

(def cli-options
  [["-c" "--chunk CHUNK"]
   ["-f" "--help"]])

(defn -main "The main entrypoint for running SpiralWeb as a command line tool."
  [& args]
  (let [opts (parse-opts args cli-options)]
    (case (first (:arguments opts))
      "tangle" (tangle (rest (:arguments opts)))
      "help" (println "Help!"))))
