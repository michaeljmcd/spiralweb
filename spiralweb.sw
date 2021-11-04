@doc SpiralWeb [out=doc/spiralweb.md]
% SpiralWeb--A Literate Programming System
% Michael McDermott
% October 11, 2017

# SpiralWeb--A Literate Programming System #

SpiralWeb was born out of a certain discontent with existing literate
programming tools. Most notably, they are almost universally dependent on a
TeX or LaTeX toolchain. From a historical point of view, this is
understandable, as the birth of the two systems (TeX and Literate
Programming) were tied, even for their creator.

However, I do not really care for composing in TeX for the same reason I
do not care to compose in HTML (despite the fact that I could write HTML in
my sleep, largely thanks to an abundance of time doing web development):
the markup is simply too distracting, requiring far too much thought to be
put into markup and not enough into content.

Another big itch that SpiralWeb aims to scratch, is making the build
process simpler. With current tools (mostly, I am thinking of noweb here),
writing build scripts is annoying as it requires respecifying the entire
web structure within the build to make it work. As a direct result, updates
to program structures must be made in at least three places: the web
itself, the tangling portion of the build, and the weaving portion of the
build.

SpiralWeb, however, will integrate the functionality of the `cpif` script
from noweb.

## Usage ##

SpiralWeb aims to be an LP system that is easier to use for a production
system than most of the systems in existence. By default, SpiralWeb expects
a list of web files (we name them as `.sw` files, but any other extension
can be used as well).

We will define our target usage succinctly, in the form of the man page for
the executable `spiralweb`.

@code Man Page [out=doc/spiralweb.1.md,lang=markdown]
% SPIRALWEB(1) SpiralWeb User Manuals
% Michael McDermott
% October 11, 2017

# NAME

spiralweb - literate programming system

# SYNOPSIS

spiralweb command [*options*] [*web-file*]...

# DESCRIPTION

SpiralWeb is a literate programming system that uses lightweight text
markup (Markdown, with Pandoc extensions being the only option at the
moment) as its default backend and provides simple, pain-free build
integration to make building real-life systems easy.

When invoked, SpiralWeb performs both tangling (the process of extracting
source code from literate files) and weaving (the process of producing
documentation from literate files) simultaneously.

A literate file (or web, denoted by a .sw extension, by convention though
not by necessity) is made up of the following directives:

`@@doc (Name)? ([option=value,option2=value2...])?`

:   Denotes a document chunk. At the moment, the only option that is used
is the `out` parameter, which specifies a path (either absolutely or
relative to the literate file it appears in) for the woven output to be
written to.

`@@code (Name)? ([option=value,option2=value2...])?`

: Denotes the beginning of a code chunk. At present, the following options
are used:

. `out` which specifies a path (either absolutely or relative to the
literate file it appears in) for the tangled output to be written to.
. `lang` which specifies a language that the code is written in. This
attribute is not used except in the weaver, which uses it when emitting
markup, so that the code can be highlighted properly.

`@@<Name>`

: Within a code chunk, this indicates that another chunk will be inserted
at this point in the final source code. It is important to note that
SpiralWeb is indentation-sensitive, so any preceding spaces or tabs before
the reference will be used as the indentation for every line in the chunks
output--even if there is _also_ indentation in the chunk.

`@@@@`

: At any spot in a literate file, this directive results in a simple `@@`
symbol.  

# OPTIONS

At least one command must be specified, and the command can be one of the
following:

`tangle`
:  Extracts the compiler-readable source from each web provided at the
   command line.

`weave`
:  Creates backend-ready source for generating documentation.

`help`
:  Prints out a help message and exits.

`edn`
:  For debugging purposes. This command reads and parses the web and then
   dumps the structure in EDN format.

If no files are specified at the command line, the web will be read from
stdin.

The following options apply to each of the commands listed above, except
help:

-c *CHUNK*, \--chunk=*CHUNK*
: Specifies one or more chunks to be tangled/woven

-f, \--force
: Ensures that any output will be written out, no matter what. By default,
    SpiralWeb first checks to see if the destination already exists and has
    identical contents, performing no write if this is so. With this
    option, the file must be written.
@end

## Parsing a Web ##

We will be using a recursive descent parser implemented with a library for
Clojure named Edessa^[edessaWebsite]. This means that we will use semantic
actions at the terminals to the grammar that will produce our internal
representation of a web. We will build this grammar up in two layers,
one that deals in in the core tokens and another layer that
assembles those into chunks off of which the remaining operations will be
performed.

Our representation for tokens will be simple maps with `:type` and `:value`
keys on them, like the following for the `@doc` token:

    {:type :doc-directive :value "@doc"}

This will keep our representations fairly light and easy to work with.

### Tokens ###

We can identify a list of tokens based on our earlier description of the
SpiralWeb language.

The first set of tokens are the directives that begin and end chunks.

* `@@doc` - begin a documentation chunk.
* `@@code` - begin a code chunk.
* `@@end` - to end a code block.

The existence of these three implies a fourth, a way to escape the at
symbol, which we designated as `@@`. Document and code chunks can have
property lists, which imply the need for the following tokens.

* `[`
* `]`
* `=`
* `,`

Finally, we have long strings of text and places where whitespace is
permitted. From this, we give a definition of the basic tokens that make up
the grammar.

@code Tokens
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
    (parser (not-one-of [\@@ \[ \] \= \, \newline])
            :name "Non-Reserved Characters"))
   :using (fn [x] {:type :text :value (apply str x)})
   :name "Text Token"))

(def code-end
  (parser (literal "@@end")
          :using (fn [_] {:type :code-end :value "@@end"})
          :name "Code End"))

(def doc-directive
  (parser (literal "@@doc")
          :using (fn [_] {:type :doc-directive :value "@@doc"})))

(def code-directive
  (parser (literal "@@code")
          :using (fn [_] {:type :code-directive :value "@@code"})))

(def at-directive
  (parser (literal "@@@@")
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
@end

The intent of most of these should be fairly obvious, but we include tests
below for completeness's sake.

@code Parser Tests
(deftest text-tests
  (is (= [{:type :text :value "asdf"}]
         (result (apply-parser t-text "asdf"))))
  (is (failure? (apply-parser t-text "@@foo")))
  (is (failure? (apply-parser t-text "[foo")))
  (is (failure? (apply-parser t-text "]foo")))
  (is (failure? (apply-parser t-text "=foo")))
  (is (failure? (apply-parser t-text ",foo")))
  (is (failure? (apply-parser t-text "\nfoo"))))

(deftest code-end-tests
  (is (= [{:type :code-end :value "@@end"}]
         (result (apply-parser code-end "@@end"))))
  (is (failure? (apply-parser code-end "@@en"))))

(deftest doc-directive-tests
  (is (= [{:type :doc-directive :value "@@doc"}]
         (result (apply-parser doc-directive "@@doc"))))
  (is (failure? (apply-parser doc-directive "@@do"))))

(deftest code-directive-tests
  (is (= [{:type :code-directive :value "@@code"}]
         (result (apply-parser code-directive "@@code"))))
  (is (failure? (apply-parser code-directive "@@cod"))))

(deftest at-directive-tests
  (is (= [{:type :at-directive :value "@@"}]
         (result (apply-parser at-directive "@@@@"))))
  (is (failure? (apply-parser at-directive "@@"))))

(deftest comma-directive-tests
  (is (= [{:type :comma :value ","}]
         (result (apply-parser comma ",33"))))
  (is (failure? (apply-parser comma "33"))))
@end

### Grammar ###

A web is, at the end of the day, a web of chunks. This idea is easy to
represent. Most of these rules require predicates to match tokens. We will
define these first in order to simplify what follows.

@code Token Predicates
(defn- code-end? [t] (= (:type t) :code-end))
(defn- prop-token? [t] (= (:type t) :properties))
@end

Which leads us to the main rule for parsing a web.

@code Web Rule
(def web (star 
          (choice 
           code-definition 
           doc-definition 
           doclines)))
@end

The definition starts with the explicit chunk definitions and then uses
`doclines` as a fallback. Let's consider the code definition first.

@code Code Chunk Rule
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
@end

Then the document definition will also seem pretty straightforward:

@code Doc Chunk Rule
(def doc-definition
(parser (then doc-directive t-text (optional property-list) (discard nl) doclines)
        :using
        (fn [x]
          (let [[_ n & lines :as all-tokens] (filter (comp not nil?) x)
                props (flatten (map :value (filter prop-token? all-tokens)))]
            {:type :doc
             :options (proplist->map props)
             :name (-> n :value trim) :lines (filter (comp not prop-token?) lines)}))))
@end

Both code and documentation chunks allow properties to be associated with
the chunk. This is to support output and formatting options. A property
list is just a series of name-value pairs surrounded by brackets.

@code Property List Rule
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
@end

The core content of a code chunk is obviously a series of lines of code.

@code Code Line Rule
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
@end

Most of these options are simply unescaped bits of text. The one chunk that
stands out is chunk references. These are the heart of a web, the linking
between different code chunks.

@code Chunk Reference Rule
(def chunkref
  (parser
   (then
    (star non-breaking-ws)
    (match \@@) (match \<)
    (plus (not-one-of [\> \newline]))
    (match \>)
    (star non-breaking-ws))
   :using
   (fn [x]
     (let [ref-text (apply str x)
           trimmed-ref-text (trim ref-text)]
       {:type :chunk-reference
        :name (subs trimmed-ref-text 2 (- (count trimmed-ref-text) 1))
        :indent-level (index-of ref-text "@@<")}))
   :name "Chunk Reference"))
@end

Rolling all the way back up to the top, we have ignored document lines.
This is largely because document lines are easy so we define it here.

@code Document Line Rule
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
@end

Now, Clojure's loading encourages a bottom-up listing of functionality
so we will restate our parsing rules accordingly.

@code Parsing Rules
@<Document Line Rule>
@<Chunk Reference Rule>
@<Property List Rule>
@<Code Line Rule>
@<Code Chunk Rule>
@<Doc Chunk Rule>
@<Web Rule>
@end

### Tests ###

@code [out=test/spiralweb/parser_test.clj]
(ns spiralweb.parser-test
 (:require [clojure.test :refer :all]
           [spiralweb.parser :refer :all]
           [edessa.parser :refer [success? failure? apply-parser result]]
           [taoensso.timbre :as t :refer [debug error]]))

(deftest nl-tests
 (is (success? (apply-parser nl [\newline])))
 (is (failure? (apply-parser nl nil)))
 (is (failure? (apply-parser nl "asdf"))))

(deftest non-breaking-ws-tests
 (is (= '[\space] (result (apply-parser non-breaking-ws [\space]))))
 (is (success? (apply-parser non-breaking-ws [\space])))
 (is (failure? (apply-parser non-breaking-ws [\a \space]))))

@<Parser Tests>
(deftest proplist-to-map-tests
  (is (= {"asdf" 1 "1 2 3" 4}
         (proplist->map [{:type :property :value {:name "asdf" :value 1}}
                         {:type :property :value {:name "1 2 3" :value 4}}]))))

(deftest code-definition-tests
 (let [cb "@@code asdf asdf [a=b]\nasdfasdf\nddddd\n  @@<asdf>\n@@end"
       exp '[{:type :code, :options {"a" "b"}, :name "asdf asdf", :lines ({:type :text, :value "asdfasdf"} {:type :newline, :value "\n"} {:type :text, :value "ddddd"} {:type :newline, :value "\n"} {:type :text, :value "  "} {:type :chunk-reference, :name "asdf", :indent-level 0} {:type :newline, :value "\n"})}]
       act (apply-parser code-definition cb)]
  (is (= exp (result act)))
  (is (success? act))))
@end

### Conclusion ###

In order to make all this code useful, we need to assemble it into a module
to be used in our codebase.

@code Parser Module [out=src/spiralweb/parser.clj]
(ns spiralweb.parser
  (:require [clojure.string :refer [starts-with? trim index-of]]
            [taoensso.timbre :as t :refer [debug error]]
            [edessa.parser :refer :all]))

@<Tokens>
@<Token Predicates>
@<Parsing Rules>
@end

## Core Operations

There are two core operations on a literate programming: tangling (whereby
we transform a web into executable source code) and weaving (whereby we
transform a web into documentation). In order to keep the discussion of the
individual functions simple, we will outline the module below.

@code Core Module [out=src/spiralweb/core.clj]
(ns spiralweb.core
 (:require [spiralweb.parser :refer [web]]
           [taoensso.timbre :refer [info debug]]
           [edessa.parser :refer [apply-parser failure? input-remaining? result]]))

@<Chunk Utilities>
@<Tangling>
@<Weaving>
@end

### Chunk Utilities ###

These are used throughout the surrounding sections, so we will define them
here.

@code Chunk Utilities
(defn chunk-content [c]
  (->> c :lines (map :value) (apply str)))

(defn is-code-chunk? [c]
  (= (:type c) :code))

(defn output-path 
  "Accepts a chunk and returns its given output path, if any."
  [c]
  (get-in c [:options "out"]))

(defn has-output-path?
  "Examines a chunk map and indicates whether there is an output path specified on the chunk."
  [c]
  (some? (output-path c)))

(defn is-chunk-reference? [c]
  (= :chunk-reference (:type c)))
@end

### Tangling

Next, we turn our attention to the `tangle` function, as it is the one needed
to get to the point where we can weave. Tangling occurrs in two phases.
First, we expand all of our code chunks. Multiple specifications of the
same chunk are concatenated together and chunk references are expanded
until only strings need to be written out.

In the second phase, we are interested in outputting our results. The main
focus of SpiralWeb is build situations where we need to write each of our
webs out to a source tree. However, it only makes sense to ensure that
SpiralWeb works with either methodology. Our output strategy will be:

I.  If the parameter `chunks` includes a list, we output each chunk in that
    list, and no others.
II.  If no list has been passed in, but a chunk named `*` exists, we output
     that chunk (the `*` chunk is considered the "root chunk" in this case).
III.  If neither of the previous conditions matches and there are one or
      more chunks with an `out` parameter, we output all of them.
IV.  If none of the above match, we raise an exception indicating the
     problem.

Understanding that "output", in this context means to write a chunk's lines
out to the location specified by the `out` option, if it exists, and to
write them to `stdout`, if it does not.

Generally speaking, tangling occurs from files. This being a Unix-style
command-line, we don't want to mandate a file, but that will be most
common. So we define a function that we expect to be called from the CLI
tool that will accept a list of paths and output chunks and tangles each in
turn.

@code Tangle
(defn tangle
  "Accepts a list of files, extracts code and writes it out."
  ([files output-chunks]
   (doseq [f files]
     ; TODO: error handling
     (info "Tangling file " f)
     (tangle-text (slurp f) output-chunks)))
  ([files] (tangle files nil)))

(defn edn-web
  "Accepts a list of paths and produces a map of paths to parsed webs."
  [paths]
  (letfn [(edn-web-inner [result paths]
            (cond
              (empty? paths) result
              :else
              (recur 
                (assoc result
                       (first paths) 
                       (refine-code-chunks (slurp (first paths))))
                (rest paths))))]
    (edn-web-inner {} paths)))
@end

This definition postpones the work of actually tangling the individual
webs to the function `tangle-text`. We will define that next:

@code Tangle Text
(defn output-code-chunks [chunks]
  (doseq [chunk chunks]
    (info "Preparing to output chunk " (:name chunk))

    (if (has-output-path? chunk)
      (spit (output-path chunk) (chunk-content chunk))
      (println (chunk-content chunk)))))

(defn tangle-text 
  "Accepts an unparsed web as text and a list of chunks to be output. This function will parse the input text and use the standard method to output the chunks."
  [txt output-chunks]
  (let [chunks (refine-code-chunks txt)]
   ;(info chunks)
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
@end

`refine-code-chunks` builds the chunk list from which we pick the relevant
portions from output. To do this, we define a simple pipeline that applies
the parser to the input text, extracts code chunks, combines chunks of the
same name (concatenating the contents) and expands out the references.

@code Refine Code Chunks
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
@end

Most of this is fairly straightforward. The most interesting bit was to
expand out the code references. Because this forms a graph of dependencies
between code chunks, we will topographically sort the code chunks and
expand them in order. This allows us to deal with transitive references and
has the nice benefit of giving us a way to identify loops.

@code Expand Code References
(defn- append-chunk [result chunk]
  (letfn [(append-lines [x] (concat (:lines chunk) x))
          (append-options [x] (merge (:options x) (:options chunk)))]
    (-> result
      (update-in [(:name chunk) :lines] append-lines)
      (update-in [(:name chunk) :options] append-options))))

(defn combine-code-chunks [result chunks]
  (let [chunk (first chunks)]
    (cond
      (empty? chunks)
        result
      (not (is-code-chunk? chunk))
        (recur result (rest chunks))
      (contains? result (:name chunk))
        (recur
         (append-chunk result chunk)
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
      (str "ERROR! Circular reference." leftovers))))

(defn expand-refs [chunk all-chunks]
  (letfn [(expand-refs-inner [lines all-chunks result]
            (let [line (first lines)]
              (cond
                (empty? lines) result
                (is-chunk-reference? line)
                (recur (rest lines)
                       all-chunks
                       (concat (reverse (-> all-chunks (get (:name line)) :lines)) result))
                :else (recur (rest lines) all-chunks (cons line result)))))]
   (debug "Expanding " chunk)
    (assoc chunk
          :lines
           (reverse (expand-refs-inner (:lines chunk) all-chunks [])))))

(defn expand-chunks 
  "Accepts a map of chunks (name -> chunk) and an order of names and expands the chunks in that order."
  [queue chunks]
  (if (empty? queue)
    chunks
    (let [cn (first queue)]
      (recur (rest queue)
             (assoc chunks
                    cn
                    (expand-refs (get chunks cn) chunks))))))

(defn expand-code-refs
  "Accepts a map of chunks (the key being the name of the chunk, value being the unique value."
  [chunks]
  (let [chunk-seq (topologically-sort-chunks chunks)]
   (debug chunk-seq)
    (expand-chunks chunk-seq chunks)))
@end

Finally, we bundle all this code up under the Tangle section we defined
earlier.

@code Tangling
@<Expand Code References>
@<Refine Code Chunks>
@<Tangle Text>
@<Tangle>
@end

### Tests

We then define tests for tangling in order to validate that our
understanding is solid.

@code Tangling Tests [out=test/spiralweb/core_test.clj]
(ns spiralweb.core-test
 (:require [clojure.test :refer :all]
           [clojure.java.io :as io]
           [spiralweb.core :refer :all]
           [edessa.parser :refer [success? failure? apply-parser result]]
           [taoensso.timbre :as t :refer [debug error info merge-config!]]))

(merge-config! {:min-level :error :appenders {:println (t/println-appender {:stream *err*})}})

(deftest output-path-tests
  (is (= "foo.txt"
         (output-path {:type :code :options {"out" "foo.txt"}}))))

(deftest tangle-edge-case-tests
 (let [circular-text "@@code a\n@@<b>\n@@end\n@@code b\n@@<a>\n@@end"
       result (tangle-text circular-text [])]
    (is (= nil result))))
@end

Let us next define a test that will validate a simple web tangles
correctly. Let's start by defining a simple sample web and then write a
confirmation test for it.

@code Simple Test Web [out=test-resources/simple.sw]
 Lorem ipsum dolor sit amet, consectetur adipiscing elit. Praesent faucibus tempus ex, id consequat ex. Mauris convallis dapibus metus eu lobortis. Nulla interdum consectetur varius. Fusce a eros dolor. Orci varius natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Cras orci justo, sagittis sit amet condimentum at, posuere id nisl. Vestibulum eleifend tempus justo ac dapibus. Ut eros enim, hendrerit ut porttitor sed, bibendum et erat. Integer vitae faucibus est. Suspendisse vitae congue sapien. Nulla nulla tortor, varius id urna vel, convallis blandit leo.

Morbi id vehicula mi, ac luctus nisl. Donec imperdiet est bibendum libero bibendum, a porttitor mi imperdiet. Vivamus sit amet tempor metus. Etiam convallis lectus id lorem pretium sodales. Suspendisse lacinia auctor massa et ultrices. Vivamus quis ante ligula. Proin sagittis turpis consectetur turpis vulputate, non efficitur urna consectetur. Duis tincidunt volutpat risus, a vulputate risus porttitor nec. Nam ac elit eget ligula feugiat porttitor. In hac habitasse platea dictumst. Curabitur sollicitudin urna a pretium aliquam. Etiam sit amet metus tellus. Vestibulum a augue quis nisl pretium condimentum.

Suspendisse vulputate volutpat dolor, non accumsan est. Praesent eu dui libero. Nunc ut fringilla nulla, a euismod purus. Pellentesque habitant morbi tristique senectus et netus et malesuada fames ac turpis egestas. Mauris vitae leo iaculis, tincidunt nibh a, faucibus diam. Ut lacinia justo id dignissim accumsan. Suspendisse ac eleifend mi. Ut posuere nisl a justo condimentum, quis molestie lacus volutpat. Vestibulum auctor ex ut augue faucibus imperdiet. Etiam sollicitudin ipsum ac enim dictum, non consectetur turpis dictum. Etiam sit amet elementum quam. Sed bibendum posuere dignissim.

@@code My Code
print('Hello World')
@@end
@end

@code Tangling Tests
(defn load-resource [name] (-> name io/resource slurp))

(deftest simple-tangle-test
 (let [simple-text (load-resource "simple.sw")]
  (is (= "print('Hello World')\n\n"
         (with-out-str (tangle-text simple-text ["My Code"]))))))
@end

This, of course, tells us little about the overall state of things. Next we
will define a test built up of multiple out-of-order chunk references.

@code Related Code Chunk Example [out=test-resources/simple-related.sw]
@@code Another Example
  @@<A Third Example>
@@end

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Praesent faucibus tempus ex, id consequat ex. Mauris convallis dapibus metus eu lobortis. Nulla interdum consectetur varius. Fusce a eros dolor. Orci varius natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Cras orci justo, sagittis sit amet condimentum at, posuere id nisl. Vestibulum eleifend tempus justo ac dapibus. Ut eros enim, hendrerit ut porttitor sed, bibendum et erat. Integer vitae faucibus est. Suspendisse vitae congue sapien. Nulla nulla tortor, varius id urna vel, convallis blandit leo.

@@code Example
print('Hello World')
@@<Another Example>
@@end

Morbi id vehicula mi, ac luctus nisl. Donec imperdiet est bibendum libero bibendum, a porttitor mi imperdiet. Vivamus sit amet tempor metus. Etiam convallis lectus id lorem pretium sodales. Suspendisse lacinia auctor massa et ultrices. Vivamus quis ante ligula. Proin sagittis turpis consectetur turpis vulputate, non efficitur urna consectetur. Duis tincidunt volutpat risus, a vulputate risus porttitor nec. Nam ac elit eget ligula feugiat porttitor. In hac habitasse platea dictumst. Curabitur sollicitudin urna a pretium aliquam. Etiam sit amet metus tellus. Vestibulum a augue quis nisl pretium condimentum.

Suspendisse vulputate volutpat dolor, non accumsan est. Praesent eu dui libero. Nunc ut fringilla nulla, a euismod purus. Pellentesque habitant morbi tristique senectus et netus et malesuada fames ac turpis egestas. Mauris vitae leo iaculis, tincidunt nibh a, faucibus diam. Ut lacinia justo id dignissim accumsan. Suspendisse ac eleifend mi. Ut posuere nisl a justo condimentum, quis molestie lacus volutpat. Vestibulum auctor ex ut augue faucibus imperdiet. Etiam sollicitudin ipsum ac enim dictum, non consectetur turpis dictum. Etiam sit amet elementum quam. Sed bibendum posuere dignissim.

@@code A Third Example
if true:
  print(1 + 2)
@@end

 Class aptent taciti sociosqu ad litora torquent per conubia nostra, per inceptos himenaeos. Nam et pharetra ligula. Donec consectetur, velit sagittis pulvinar vestibulum, ipsum eros pharetra lectus, dapibus pharetra tellus quam a justo. Aliquam erat volutpat. Morbi sit amet blandit ante, nec porta magna. Pellentesque habitant morbi tristique senectus et netus et malesuada fames ac turpis egestas. Vestibulum nec odio egestas, sodales leo eu, semper turpis. Nunc aliquet laoreet ante in sagittis. Nunc a fermentum odio. Vestibulum et nisi bibendum, egestas tellus quis, molestie diam. Etiam sit amet luctus nibh. In fermentum erat ut nisi pretium, at eleifend quam imperdiet.
@end

@code Tangling Tests
(deftest related-chunk-tangle-test
 (let [text (load-resource "simple-related.sw")]
       (is (= "print('Hello World')\n  if true:\n  print(1 + 2)\n\n\n\n"
         (with-out-str (tangle-text text ["Example"]))))))
@end

@code Tangling Tests
(deftest expand-refs-simple
 (let [chunk {:type :code 
              :name "Outer"
              :options [] 
              :lines [{:type :text :value "asdf"}
                      {:type :chunk-reference :name "Inner"}
                      {:type :text :value "zzzz"}]}
      inner-chunk {:type :code :name "Inner" :lines [{:type :text :value "ggg"}]}
      all-chunks {"Outer" chunk "Inner" inner-chunk}]
   (is (= (expand-chunks ["Inner" "Outer"] all-chunks)
        {"Outer"
          {:type :code
           :name "Outer"
           :options []
           :lines [{:type :text, :value "asdf"}
                   {:type :text, :value "ggg"}
                   {:type :text, :value "zzzz"}]}
        "Inner" inner-chunk}))))
@end

Another feature of code expansion is the idea that chunks that are named
the same are concatenated together when tangling. Let's specify a test case
for this functionality.

@code Simple Concatenation [out=test-resources/simple-concat.sw]
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Praesent faucibus tempus ex, id consequat ex. Mauris convallis dapibus metus eu lobortis. Nulla interdum consectetur varius. Fusce a eros dolor. Orci varius natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Cras orci justo, sagittis sit amet condimentum at, posuere id nisl. Vestibulum eleifend tempus justo ac dapibus. Ut eros enim, hendrerit ut porttitor sed, bibendum et erat. Integer vitae faucibus est. Suspendisse vitae congue sapien. Nulla nulla tortor, varius id urna vel, convallis blandit leo. 

@@code Example
1
@@end

Morbi id vehicula mi, ac luctus nisl. Donec imperdiet est bibendum libero bibendum, a porttitor mi imperdiet. Vivamus sit amet tempor metus. Etiam convallis lectus id lorem pretium sodales. Suspendisse lacinia auctor massa et ultrices. Vivamus quis ante ligula. Proin sagittis turpis consectetur turpis vulputate, non efficitur urna consectetur. Duis tincidunt volutpat risus, a vulputate risus porttitor nec. Nam ac elit eget ligula feugiat porttitor. In hac habitasse platea dictumst. Curabitur sollicitudin urna a pretium aliquam. Etiam sit amet metus tellus. Vestibulum a augue quis nisl pretium condimentum. 

 @@code Example
 2
 @@end
@end

Which we then verify:

@code Tangling Tests
(deftest simple-concatenation-tests
 (let [text (load-resource "simple-concat.sw")]
     (is (= "1\n 2\n \n"
         (with-out-str (tangle-text text ["Example"]))))))
@end

### Weaving

Once we have tangling, we can turn our attention to weaving documentation.
Tangling is the simpler operation of the two, since it merely extracts and
outputs text. Weaving, on the other hand, requires some knowledge of the
final destination format.

Next we need to define what it means to resolve the documentation chunks.
Because we have a `@@doc` directive, we enable a single physical web to
output multiple woven documentation files. 

We can expect that we will receive an arbitrary sequence of chunks. We want
to combine all of the chunks separated by any `@@doc` directives under a
single heading. The beginning of the file can be thought of as an implicit
`@@doc` directive.

To make it clear, we would expect the following file:

    This is an example script.

    @@code test.sh
    #!/bin/sh

    echo test
    @@end

    More examples.

    @@doc Example
    
    More test.

    @@code test2.sh
    #!/bin/sh

    echo test2
    @@end

To parse in the following chunk list:

1. `doc` ("This is an example script. \\n")
2. `code` \[test.sh] ("#!/bin/sh\n   echo test")
3. `doc` ("More examples")
4. `doc` \[Example] ("More test.") 
5. `code` \[test2.sh] ("#!/bin/sh\\n  echo test2")

The end result should combine chunks 1-3 under a single documentation
chunk and chunks 4-5 under another, so that if chunks are passed to the
output sequence, we can dump those out alone.

@code Weave Text
(defn weave-text [text chunks]
 (apply-parser web text))
@end

@code Weaving
@<Weave Text>

(defn weave
 "Accepts a list of files, extracts the documentation and writes it out."
 ([files] (weave files nil))
 ([files chunks]
  (doseq [f files]
     ; TODO: error handling
     (info "Tangling file " f)
     (weave-text (slurp f) chunks))))
@end

## The Command Line Application ##

In the previous sections, we defined the command-line syntax for the
invocation of `spiralweb`. Here we take that specification and combine it
with the APIs we defined previously to put it all together and create a
usable command line application.

Fortunately, this is relatively simple to assemble from the pieces that we
have already assembled.

@code SpiralWeb CLI [out=src/spiralweb/cli.clj]
(ns spiralweb.cli
 (:gen-class)
 (:require [spiralweb.core :refer [tangle edn-web weave]]
           [clojure.tools.cli :refer [parse-opts]]
           [taoensso.timbre :as t :refer [merge-config!]]
           [clojure.pprint :refer [pprint]]))

(def cli-options
  [["-c" "--chunk CHUNK"]
   ["-f" "--help"]])

(defn -main "The main entrypoint for running SpiralWeb as a command line tool."
  [& args]
  (merge-config! {:min-level [[#{"spiralweb.core"} :error]
                              [#{"edessa.parser"} :error]]
                  :appenders {:println (t/println-appender {:stream *err*})}})

  (let [opts (parse-opts args cli-options)]
    (case (first (:arguments opts))
      "tangle" (tangle (rest (:arguments opts)))
      "weave" (weave (rest (:arguments opts)))
      "edn" (pprint (edn-web (rest (:arguments opts))))
      "help" (println "Help!"))))
@end

### Packaging

TODO

## Conclusion ##

As we wrap up, our main conclusions are to look forward to the sorts of
advancements we would like to see in the next version:

* Indexing--unlike noweb and funnelweb, we did not include indexing. The
  plan would be to add an `@@index` directive to the grammar that allows
  for web-wide and chunk-specific indexing.
* Allow external webs to be included in a web.

## References ##

[^edessaWebsite]: (Edessa on Github)[https://github.com/michaeljmcd/edessa]

// vim: set tw=75 ai: 
