(ns spiralweb.core
 (:require [spiralweb.parser :refer [web]]
           [edessa.parser :refer [apply-parser failure? input-remaining? result]]))

(defn chunk-content [c]
  (->> c :lines (map :value) (apply str)))

(defn is-code-chunk? [c]
  (= (:type c) :code))

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


