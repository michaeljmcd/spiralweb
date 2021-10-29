@doc Vim Syntax File for SpiralWeb [out=swvim.md]
# Vim Syntax File for SpiralWeb 

Even though, at this early date, the first version of SpiralWeb is not yet
complete, life has been unpleasant without a good Vim mode for this nascent
literate programming system.

So, we will define one here based on my previous work on noweb.vim.

First, there is some standard boilerplate that I picked up for clearing out
the syntax before defining any additional work:

@code sw.vim [out=sw.vim]
" Remove any old syntax stuff hanging around
if version < 600
  syntax clear
elseif exists("b:current_syntax")
  finish
  w
endif
@end

Before continuing, we define parameters for the backend and programming
language syntax.

@code sw.vim
if !exists("spiralweb_backend")
    let spiralweb_backend = "markdown" " this is the only backend at the moment
endif
@end

Next, we define the base syntax to be that of the backend. Afterwards, we
set the code regions to default to the language in question.

@code sw.vim
if version < 600
    execute "source <sfile>:p:h/" . spiralweb_backend . ".vim"
else
    execute "runtime! syntax/" . spiralweb_backend . ".vim"

    if exists("b:current_syntax")
        unlet b:current_syntax
    endif
endif

syntax match codeChunkStart "^@@code .*$" display
syntax match codeChunkEnd "^@@end$" display
highlight link codeChunkStart Type
highlight link codeChunkEnd Type
if !exists("spiralweb_language")
    let spiralweb_language = "nosyntax"
endif

execute "syntax include @@Code syntax/" . spiralweb_language . ".vim"
" syntax include @@Code syntax/vim.vim
syntax region codeChunk start="^@@code .*$" end="^@@end$" contains=@@Code containedin=ALL keepend
@end

Finally, we add instructions to do code folding (iff the option is set).

@code sw.vim
if exists("spiralweb_fold_code") && spiralweb_fold_code == 1
    set foldmethod=syntax
    syntax region codeChunk start="^@@code .*$" end="^@@end$" transparent fold containedin=ALL keepend
endif
@end

In conclusion, this gets us a basic, serviceable vim-mode for use with
SpiralWeb. In the future, it would be nice to integrate the `out`
parameters into the vim syntax so that webs with multiple languages have
auto-detect up and running.

// vim: set tw=75 ai: 
