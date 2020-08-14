(ns spiralweb.core
 (:require [clojure.string :refer [starts-with? trim index-of]]
           [clojure.core.reducers :refer [fold]]))

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
{:parser (str "Matches " c)}
 ))

(defn not-one-of [chars] 
 (with-meta
 (fn [inp]
  (let [[x & xs] inp]
      (if (or (empty? inp)
              (some (partial = x) chars))
       (fail inp)
       (succeed x xs))))
 {:parser (str "Not one of [" chars "]")}
 ))

(defn zero-or-more [parser] 
 (letfn [(accumulate [inp xs]
          ;(println "Z+: " (parser-name parser) " Input: " inp)
          (if (empty? inp)
           (succeed (reverse xs) inp)
             (let [r (parser inp)]
               (if (failure? r) 
                (succeed (reverse xs) inp)
                (recur (second r) (concat (first r) xs))))
              )
          )]
  (with-meta
    (fn [inp] (accumulate inp []))
    {:parser (->> parser parser-name (str "Zero or more "))})
  ))

(def star zero-or-more)

(defn por 
 ([] (with-meta fail {:parser "Fail"}))
 ([parser1] (with-meta parser1 {:parser (parser-name parser1)}))
 ([parser1 parser2]
  (with-meta
 (fn [inp]
  (let [r1 (parser1 inp)]
   (if (failure? r1)
    (parser2 inp)
    r1)))
 {:parser (str (parser-name parser1) " OR " (parser-name parser2))}
 ))
 ([parser1 parser2 & parsers] (fold por (concat [parser1 parser2] parsers))))

(def || por)

(defn optional [parser]
 (with-meta
  (|| parser epsilon)
  {:parser (str (parser-name parser) "?")}))

(defn one-of [chars]
 (apply por (map #(match %) chars)))

(defn using [parser transformer]
 (with-meta
 (fn [inp]
   (let [[data state :as r] (parser inp)]
    (if (failure? r)
     r
     (succeed (transformer data) state))))
 {:parser (str (parser-name parser) " [+ Transformer]")}
 ))

(defn literal [lit]
 (with-meta 
     (fn [inp]
      (if (starts-with? inp lit)
       (succeed lit (subs inp (count lit)))
       (fail inp)))
    {:parser (str "Literal: " lit) }
     ))

(defn then 
 ([] (with-meta epsilon {:parser "Epsilon (empty)"}))
 ([parser1] (with-meta parser1 (meta parser1)))
 ([parser1 parser2]
  (with-meta
     (fn [inp]
     (let [[data1 remaining1 :as r1] (parser1 inp)]
      (if (success? r1)
       (let [[data2 remaining2 :as r2] (parser2 remaining1)]
        (if (success? r2)
         (succeed (concat data1 data2) remaining2)
         (fail inp)))
       (fail inp))))
     {:parser (str (parser-name parser1) " THEN " (parser-name parser2))}
     ))
 ([parser1 parser2 & parsers] (fold then (cons parser1 (cons parser2 parsers)))))

(def |> then)

(defn one-or-more [parser]
 (then parser (star parser)))

(def plus one-or-more)

; Spiralweb language definition

(def non-breaking-ws (one-of [\space \tab]))

(def nl 
 (using (match \newline)
  (fn [x] {:type :newline :value (str \newline)})))

(def t-text 
 (using 
  (plus (not-one-of [\@ \[ \] \= \, \newline]))
  (fn [x] {:type :text :value (apply str x)})
  ))

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
  (fn [_] {:type :comma :value "," })))

(def t-equals 
 (using (match \=)
  (fn [_] {:type :equals :value "=" })))

(def open-proplist 
 (using (match \[)
  (fn [_] {:type :open-proplist :value "["})))

(def close-proplist 
 (using (match \])
  (fn [_] {:type :close-proplist :value "]"})))

(def chunkref
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
   :indent-level (index-of ref-text "@<")})
  )))

(def docline 
      (|| t-text
          nl 
          at-directive 
          comma
          t-equals
          open-proplist
          close-proplist))

(def codeline 
      (|| t-text
          nl 
          at-directive 
          comma
          t-equals
          open-proplist
          close-proplist
          chunkref))

(def doclines (plus docline))

(def property
 (using (then t-text t-equals t-text)
  (fn [x]
   (let [scrubbed (filter (comp not nil?) x)]
    {:type :property :value {:name (-> scrubbed first :value trim) 
                             :value (-> scrubbed (nth 2) :value trim)}}))))

(def property-sequence (|| (then comma property) property))
 
(def property-list
 (using (then open-proplist (star property-sequence) close-proplist (star non-breaking-ws))
  (fn [x]
   {:type :properties :value
   (filter (fn [y] (and (not (nil? y))
                         (= :property (:type y)))) x)})))

(defn- prop-token? [t] (= :properties (:type t)))

(def doc-definition
 (using (|> doc-directive t-text (optional property-list) nl doclines)
    (fn [x]
        (let [[_ n & lines :as all-tokens] (filter (comp not nil?) x)
              props (flatten (map :value (filter prop-token? all-tokens)))]
         {:type :doc :options props
                 :name (-> n :value trim) :lines (filter (comp not prop-token?) lines)}))
  ))

(def code-definition
 (using (|> code-directive t-text (optional property-list) nl doclines)
    (fn [x]
        (let [[_ n & lines :as all-tokens] (filter (comp not nil?) x)
              props (flatten (map :value (filter prop-token? all-tokens)))]
         {:type :doc :options props
                 :name (-> n :value trim) :lines (filter (comp not prop-token?) lines)}))
  ))
