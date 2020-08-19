(ns spiralweb.core
  (:require [clojure.string :refer [starts-with? trim index-of]]
            [clojure.core.reducers :refer [fold]]
            [clojure.tools.cli :refer [parse-opts]]
            [taoensso.timbre :as t :refer [debug error]]))

; General parsing functions and combinators.

(defn succeed {:parser "Succeed"} [v inp]
  (if (seq? v)
    [v inp]
    [[v] inp]))

(def epsilon (with-meta (partial succeed nil) {:parser "Epsilon (empty)"}))

(defn fail {:parser "Fail"} [_] [])

(defn failure? [r] (= r []))

(def success? (comp not failure?))

(defn parser-name [parser] (-> parser meta :parser))

(defn match [c]
  (with-meta
    (fn  [inp]
      (if (and (not (empty? inp))
               (= (first inp) c))
        (succeed c (rest inp))
        (fail inp)))
    {:parser (str "Matches " c)}))

(defn not-one-of [chars]
  (with-meta
    (fn [inp]
      (let [[x & xs] inp]
        (if (or (empty? inp)
                (some (partial = x) chars))
          (fail inp)
          (succeed x xs))))
    {:parser (str "Not one of [" chars "]")}))

(defn zero-or-more [parser]
  (letfn [(accumulate [inp xs]
            (debug "Z*: " (parser-name parser) " Input: " inp)
            (if (empty? inp)
              (succeed (reverse xs) inp)
              (let [r (parser inp)]
                (debug "Z*: Parser " (parser-name parser) " yielded " r)
                (if (failure? r)
                  (do
                    (debug "Z*: Hit end of matches, returning " (succeed (reverse xs) inp))
                    (succeed (reverse xs) inp))
                  (recur (second r) (concat (first r) xs))))))]

    (with-meta
      (fn [inp] (accumulate inp []))
      {:parser (->> parser parser-name (str "Zero or more "))})))

(def star zero-or-more)

(defn choice
  ([] (with-meta fail {:parser "Fail"}))
  ([parser1] (with-meta parser1 {:parser (parser-name parser1)}))
  ([parser1 parser2]
   (with-meta
     (fn [inp]
       (let [r1 (parser1 inp)]
         (if (failure? r1)
           (parser2 inp)
           r1)))
     {:parser (str (parser-name parser1) " OR " (parser-name parser2))}))
  ([parser1 parser2 & parsers] (fold choice (concat [parser1 parser2] parsers))))

(def || choice)

(defn optional [parser]
  (with-meta
    (|| parser epsilon)
    {:parser (str (parser-name parser) "?")}))

(defn one-of [chars]
  (apply choice (map #(match %) chars)))

(defn using [parser transformer]
  (with-meta
    (fn [inp]
      (let [[data state :as r] (parser inp)]
        (if (failure? r)
          r
          (succeed (transformer data) state))))
    {:parser (str (parser-name parser) " [+ Transformer]")}))

(defn then
  ([] (with-meta epsilon {:parser "Epsilon"}))
  ([parser1] (with-meta parser1 (meta parser1)))
  ([parser1 parser2]
   (with-meta
     (fn [inp]
       (debug "Entering Then combinator.")
       (let [[data1 remaining1 :as r1] (parser1 inp)]
         (debug "Parser 1 [" (parser-name parser1) "] yielded " r1)
         (if (success? r1)
           (let [[data2 remaining2 :as r2] (parser2 remaining1)]
             (debug "Parser 2 [" (parser-name parser2) "] yielded " r2)
             (if (success? r2)
               (succeed (concat data1 data2) remaining2)
               (do
                 (debug "Parser 2 [" (parser-name parser2) "] failed, terminating chain.")
                 (fail inp))))
           (do
             (debug "Parser 1 [" (parser-name parser1) "] failed, terminating chain.")
             (fail inp)))))
     {:parser (str (parser-name parser1) " THEN " (parser-name parser2))}))
  ([parser1 parser2 & parsers] (fold then (cons parser1 (cons parser2 parsers)))))

(def |> then)

(defn literal [lit]
  (with-meta
    (apply then (map match lit))
    {:parser "Literal [" lit "]"}))

(defn one-or-more [parser]
  (then parser (star parser)))

(def plus one-or-more)

; Spiralweb language definition

(def non-breaking-ws
  (with-meta
    (one-of [\space \tab])
    {:parser "Non-breaking whitespace"}))

(def nl
  (using (match \newline)
         (fn [x] {:type :newline :value (str \newline)})))

(def t-text
  (with-meta
    (using
     (plus
      (with-meta
        (not-one-of [\@ \[ \] \= \, \newline])
        {:parser "Non-Reserved Characters"}))
     (fn [x] {:type :text :value (apply str x)}))
    {:parser "Text Token"}))

(def code-end
  (with-meta
    (using (literal "@=")
           (fn [_] {:type :code-end :value "@="}))
    {:parser "Code End"}))

(def doc-directive
  (using (literal "@doc")
         (fn [_] {:type :doc-directive :value "@doc"})))

(def code-directive
  (using (literal "@code")
         (fn [_] {:type :code-directive :value "@code"})))

(def at-directive
  (using (literal "@@")
         (fn [_] {:type :at-directive :value "@@"})))

(def comma
  (using (match \,)
         (fn [_] {:type :comma :value ","})))

(def t-equals
  (using (match \=)
         (fn [_] {:type :equals :value "="})))

(def open-proplist
  (using (match \[)
         (fn [_] {:type :open-proplist :value "["})))

(def close-proplist
  (using (match \])
         (fn [_] {:type :close-proplist :value "]"})))

(def chunkref
  (with-meta
    (using
     (then
      (star non-breaking-ws)
      (match \@) (match \<)
      (plus (not-one-of [\> \newline]))
      (match \>)
      (star non-breaking-ws))
     (fn [x]
       (let [ref-text (apply str x)
             trimmed-ref-text (trim ref-text)]
         {:type :chunk-reference
          :name (subs trimmed-ref-text 2 (- (count trimmed-ref-text) 1))
          :indent-level (index-of ref-text "@<")})))
    {:parser "Chunk Reference"}))

(def docline
  (with-meta
    (choice t-text
            nl
            at-directive
            comma
            t-equals
            open-proplist
            close-proplist)
    {:parser "Docline"}))

(def codeline
  (with-meta
    (choice t-text
            nl
            at-directive
            comma
            t-equals
            open-proplist
            close-proplist
            chunkref)
    {:parser "Codeline"}))

(def doclines (plus docline))

(def property
  (using (then t-text t-equals t-text)
         (fn [x]
           (let [scrubbed (filter (comp not nil?) x)]
             {:type :property :value {:name (-> scrubbed first :value trim)
                                      :value (-> scrubbed (nth 2) :value trim)}}))))

(def property-sequence (choice (then comma property) property))

(def property-list
  (using (then open-proplist (star property-sequence) close-proplist (star non-breaking-ws))
         (fn [x]
           {:type :properties :value
            (filter (fn [y] (and (not (nil? y))
                                 (= :property (:type y)))) x)})))

(defn- prop-token? [t] (= :properties (:type t)))

(def doc-definition
  (using (then doc-directive t-text (optional property-list) nl doclines)
         (fn [x]
           (let [[_ n & lines :as all-tokens] (filter (comp not nil?) x)
                 props (flatten (map :value (filter prop-token? all-tokens)))]
             {:type :doc :options props
              :name (-> n :value trim) :lines (filter (comp not prop-token?) lines)}))))

(defn code-end? [t] (= (:type t) :code-end))

(def code-definition
  (using (then code-directive t-text (optional property-list) nl (plus codeline) code-end)
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

(defn extract-inner [result chunks]
 (let [chunk (first chunks)]
 (cond
  (empty? chunks) 
    result
  (not (is-code-chunk? chunk)) 
    (recur result (rest chunks))
  (contains? result (:name chunk))
   (recur
    (update-in result [(:name chunk) :lines]
     (fn [x] (concat x (:lines chunk))))
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

(defn extract-output-chunks [webstr]
    (let [[parse-tree remaining-input] (web webstr)]
          (if (empty? remaining-input)
            (filter has-output-path? (vals (extract-inner {} parse-tree)))
            (error "Invalid web"))))

(defn tangle "Accepts a list of files, extracts code and writes it out."
 [files]
 ; TODO: handle chunk references
 ; TODO: handle targeted chunk case 
  (doseq [f files]
    (let [output-chunks (extract-output-chunks (slurp f))]
      (doseq [chunk output-chunks]
       (spit (output-path chunk) (apply str (:lines chunk)))))))

(def cli-options
  [["-c" "--chunk CHUNK"]
   ["-f" "--help"]])

(defn -main "The main entrypoint for running SpiralWeb as a command line tool." 
 [& args]
  (let [opts (parse-opts args cli-options)]
    (case (first (:arguments opts))
      "tangle" (tangle (rest (:arguments opts)))
      "help" (println "Help!"))))
