(ns build
  (:require [clojure.tools.build.api :as b]))

(def lib 'michaeljmcd/spiralweb)
(def version "1.0.0")
(def class-dir "target/classes")
(def basis (b/create-basis {:project "deps.edn"}))
(def uber-file (format "target/%s-%s-standalone.jar" (name lib) version))

(defn clean [_]
  (b/delete {:path "target"}))

(defn uber [_]
  (clean nil)
  (b/copy-dir {:src-dirs ["src" "resources"]
               :target-dir class-dir})
  (b/compile-clj {:basis basis
                  :src-dirs ["src"]
                  :class-dir class-dir})
  (b/uber {:class-dir class-dir
           :uber-file uber-file
           :main 'spiralweb.cli
           :basis basis}))

(defn weave [_]
  (b/process {:command-args ["clj" "-M:spiralweb" "weave" "spiralweb.sw"]})
  (b/process {:command-args ["clj" "-M:spiralweb" "weave" "swvim.sw"]}))

(defn tangle [_]
  (b/process {:command-args ["clj" "-M:spiralweb" "tangle" "spiralweb.sw"]})
  (b/process {:command-args ["clj" "-M:spiralweb" "tangle" "swvim.sw"]}))

(defn html [_]
  (b/process {:command-args ["pandoc" "doc/spiralweb.md" "-o" "doc/spiralweb.html" "--standalone"]})
  (b/process {:command-args ["pandoc" "doc/swvim.md" "-o" "doc/swvim.html" "--standalone"]}))
