(ns spiralweb.core)

(defn succeed [v inp]
 (if (seq? v)
  [v inp]
  [[v] inp]))

(defn fail [_] [])

(defn failure? [r] (= r []))

(defn oneof [chars] 
 (fn [inp]
  (if (some (partial = (first inp)) chars) 
   [[(first inp)] (rest inp)] 
   (fail inp))))

(defn notoneof [chars] 
 (fn [inp]
  (if (not (some (partial = (first inp)) chars))
   [[(first inp)] (rest inp)] 
   (fail inp))))

(defn zero-or-more [p] 
 (letfn [(accumulate [inp xs] 
          (let [r (p inp)] 
           (if (failure? r) 
            [(reverse xs) inp] 
            (accumulate (second r) (concat (first r) xs)))))] 
  (fn [inp] (accumulate inp []))))

(defn por [p1 p2]
 (fn [inp]
  (let [r1 (p1 inp)]
   (if (failure? r1)
    (p2 inp)
    r1))))

(defn using [p transformer]
 (fn [inp]
   (let [r (p inp)]
    (if (failure? r)
     r
     [(transformer (first r)) (second r)]))))


