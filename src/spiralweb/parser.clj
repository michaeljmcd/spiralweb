(ns spiralweb.parser
  (:require [clojure.string :refer [starts-with? trim index-of]]
            [taoensso.timbre :as t :refer [debug error]]
            [edessa.parser :refer :all]))

(def non-breaking-ws
  (parser (one-of [\space \tab])
          :name "Non-breaking whitespace"))
(def nl
  (parser (match \newline)
          :name "Newline"
          :using (fn [_] {:type :newline :value (str \newline)})))

(def t-text
  (parser
   (plus
    (parser (not-one-of [\@ \[ \] \= \, \newline])
            :name "Non-Reserved Characters"))
   :using (fn [x] {:type :text :value (apply str x)})
   :name "Text Token"))

(def code-end
  (parser (literal "@end")
          :using (fn [_] {:type :code-end :value "@end"})
          :name "Code End"))

(def doc-directive
  (parser (literal "@doc")
          :using (fn [_] {:type :doc-directive :value "@doc"})))

(def code-directive
  (parser (literal "@code")
          :using (fn [_] {:type :code-directive :value "@code"})))

(def at-directive
  (parser (literal "@@")
          :using (fn [_] {:type :at-directive :value "@"})))

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

(defn- code-end? [t] (= (:type t) :code-end))
(defn- prop-token? [t] (= (:type t) :properties))

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

(def doclines (plus docline))

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

(def property
  (parser (then
           t-text 
           t-equals
           t-text)
          :using
          (fn [x]
            (let [scrubbed (filter (comp not nil?) x)]
              {:type :property
              :value {:name (-> scrubbed first :value trim)
              :value (-> scrubbed (nth 2) :value trim)}}))))

(def property-sequence (choice 
                        (then comma property)
                        property))

(def property-list
  (parser (then open-proplist
           (star property-sequence)
           close-proplist
           (star non-breaking-ws))
          :using
          (fn [x]
            {:type :properties :value
             (filter (fn [y] (and (not (nil? y))
                                  (= :property (:type y)))) x)})))

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

(defn proplist->map [props]
  (apply hash-map
         (flatten (map (fn [x] 
                         (let [kv (:value x)]
                           [(:name kv) (:value kv)]))
                   props))))

(def code-definition
  (parser (then 
           code-directive 
           t-text 
           (optional property-list) 
           (discard nl)
           (plus codeline)
           code-end)
          :using
          (fn [x]
            (let [[_ n & lines :as all-tokens] (filter (comp not nil?) x)
                  props (flatten (map :value (filter prop-token? all-tokens)))]
              {:type :code
               :options (proplist->map props)
               :name (-> n :value trim)
               :lines (filter #(not (or (prop-token? %) (code-end? %))) lines)}))))

(def doc-definition
(parser (then doc-directive t-text (optional property-list) (discard nl) doclines)
        :using
        (fn [x]
          (let [[_ n & lines :as all-tokens] (filter (comp not nil?) x)
                props (flatten (map :value (filter prop-token? all-tokens)))]
            {:type :doc
             :options (proplist->map props)
             :name (-> n :value trim) :lines (filter (comp not prop-token?) lines)}))))

(def web (star 
          (choice 
           code-definition 
           doc-definition 
           doclines)))


