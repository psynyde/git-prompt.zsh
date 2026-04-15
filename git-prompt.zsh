# git-prompt.zsh -- stripped down (Native Zsh Colors + Custom Icons + Tags)
setopt PROMPT_SUBST

# Prefer mawk/nawk over awk for faster text processing
# mawk takes priority (fastest), nawk is fallback, awk is last resort
(( $+commands[mawk] ))  &&  : "${ZSH_GIT_PROMPT_AWK_CMD:=mawk}"
(( $+commands[nawk] ))  &&  : "${ZSH_GIT_PROMPT_AWK_CMD:=nawk}"
                            : "${ZSH_GIT_PROMPT_AWK_CMD:=awk}"

_zsh_git_prompt_git_cmd() {
    GIT_OPTIONAL_LOCKS=0 command git status --show-stash --branch --porcelain=v2 2>&1 || echo "fatal: git command failed"
}

zmodload zsh/system

function _zsh_git_prompt_async_request() {
    typeset -g _ZSH_GIT_PROMPT_ASYNC_FD _ZSH_GIT_PROMPT_ASYNC_PID

    if [[ -n "$_ZSH_GIT_PROMPT_ASYNC_FD" ]] && { true <&$_ZSH_GIT_PROMPT_ASYNC_FD } 2>/dev/null; then
        # Deregister handler BEFORE closing FD to prevent a spurious callback
        zle -F $_ZSH_GIT_PROMPT_ASYNC_FD
        exec {_ZSH_GIT_PROMPT_ASYNC_FD}<&-
        if [[ -o MONITOR ]]; then
            kill -TERM -$_ZSH_GIT_PROMPT_ASYNC_PID 2>/dev/null
        else
            kill -TERM $_ZSH_GIT_PROMPT_ASYNC_PID 2>/dev/null
        fi
    fi

    exec {_ZSH_GIT_PROMPT_ASYNC_FD}< <(
        builtin echo $sysparams[pid]

        git_tags=$(command git tag --points-at=HEAD 2> /dev/null)
        git_tags=${git_tags//$'\n'/, }

        _zsh_git_prompt_git_cmd | $ZSH_GIT_PROMPT_AWK_CMD -v TAG_STR="$git_tags" '
            BEGIN { ORS = ""; fatal = 0; oid = ""; head = ""; ahead = 0; behind = 0; untracked = 0; unmerged = 0; staged = 0; unstaged = 0; stashed = 0; }

            $1 == "fatal:" { fatal = 1; }
            $2 == "branch.oid" { oid = $3; }
            $2 == "branch.head" { head = $3; }
            $2 == "branch.ab" { ahead = $3 + 0; behind = -$4; }
            $2 == "stash" { stashed = $3; }
            $1 == "?" { ++untracked; }
            $1 == "u" { ++unmerged; }
            $1 == "1" || $1 == "2" {
                split($2, arr, "");
                if (arr[1] != ".") ++staged;
                if (arr[2] != ".") ++unstaged;
            }

            END {
                if (fatal == 1) exit(1);

                gsub("%", "%%", TAG_STR);
                print "[";

                if (head == "(detached)") {
                    print "%B%F{cyan}:" substr(oid, 1, 7) "%f%b";
                } else {
                    gsub("%", "%%", head);
                    print "%B%F{magenta}" head "%f%b";
                }

                if (behind > 0) print "" behind;
                if (ahead > 0) print "" ahead;

                print ":";

                if (unmerged > 0) print "%F{red}" unmerged "%f";
                if (staged > 0) print "%F{green}" staged "%f";
                if (unstaged > 0) print "%F{red}" unstaged "%f";
                if (untracked > 0) print "…" untracked;

                if (unmerged == 0 && staged == 0 && unstaged == 0 && untracked == 0) {
                    print "%B%F{green}%f%b";
                }

                if (stashed > 0) print " %F{blue} " stashed "%f";

                print "]";

                if (TAG_STR != "") {
                    print " %B%F{cyan}🏷 " TAG_STR "%f%b";
                }
            }
        '
    )

    command true
    read _ZSH_GIT_PROMPT_ASYNC_PID <&$_ZSH_GIT_PROMPT_ASYNC_FD
    zle -F "$_ZSH_GIT_PROMPT_ASYNC_FD" _zsh_git_prompt_callback
}

_ZSH_GIT_PROMPT_STATUS_OUTPUT=""

function _zsh_git_prompt_callback() {
    emulate -L zsh
    local old_primary="$_ZSH_GIT_PROMPT_STATUS_OUTPUT"

    if [[ -z "$2" || "$2" == "hup" ]]; then
        _ZSH_GIT_PROMPT_STATUS_OUTPUT="$(cat <&$1)"

        if [[ "$old_primary" != "$_ZSH_GIT_PROMPT_STATUS_OUTPUT" ]] ; then
            zle reset-prompt
            zle -R
        fi
        exec {1}<&-
    fi

    zle -F "$1"
    unset _ZSH_GIT_PROMPT_ASYNC_FD
}

function _zsh_git_prompt_precmd_hook() {
    _zsh_git_prompt_async_request
}

if (( $+commands[git] )); then
    autoload -U add-zsh-hook && add-zsh-hook precmd _zsh_git_prompt_precmd_hook
    function gitprompt() { echo -n "$_ZSH_GIT_PROMPT_STATUS_OUTPUT" }
else
    function gitprompt() { }
fi
