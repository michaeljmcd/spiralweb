(ns spiralweb.cli
 (:require [spiralweb.core :refer [tangle]]
           [clojure.tools.cli :refer [parse-opts]]
           [taoensso.timbre :as t :refer [merge-config!]]))

(merge-config! {:level :error})

(def cli-options
  [["-c" "--chunk CHUNK"]
   ["-f" "--help"]])

(defn -main "The main entrypoint for running SpiralWeb as a command line tool."
  [& args]
  (merge-config! {:min-level :error :appenders {:println (t/println-appender {:stream *err*})}})
  (let [opts (parse-opts args cli-options)]
    (case (first (:arguments opts))
      "tangle" (tangle (rest (:arguments opts)))
      "help" (println "Help!"))))
