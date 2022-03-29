(ns spiralweb.cli
 (:gen-class)
 (:require [spiralweb.core :refer [tangle edn-web weave]]
           [clojure.tools.cli :refer [parse-opts]]
           [clojure.string :refer [join]]
           [taoensso.timbre :as t :refer [merge-config!]]
           [clojure.pprint :refer [pprint]]))

(def cli-options
  [["-c" "--chunk CHUNK"]
   ["-f" "--help"]])

(defn -main "The main entrypoint for running SpiralWeb as a command line tool."
  [& args]
  (merge-config! {:min-level [[#{"spiralweb.core"} :error]
                              [#{"spiralweb.parser"} :error]
                              [#{"edessa.parser"} :error]]
                  :appenders {:println (t/println-appender {:stream *err*})}})

  (let [opts (parse-opts args cli-options)]
    (case (first (:arguments opts))
      "tangle" (tangle (rest (:arguments opts)))
      "weave" (weave (rest (:arguments opts)))
      "edn" (pprint (edn-web (rest (:arguments opts))))
      "help" (println "Help!"))))
