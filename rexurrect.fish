# rexurrect.fish: a fish port of rexurrect.plugin.zsh.
#
# Records each command a Rex block's shell starts as that block's last
# command, in the shared recorder-file format rexurrect reads:
#   <state dir>/recorder/<REX_BLOCK>, one line, written via temp + rename.
# State dir: $REXURRECT_STATE_DIR, else $XDG_STATE_HOME/rexurrect (if
# absolute), else ~/.local/state/rexurrect.
#
# Install: copy to ~/.config/fish/conf.d/rexurrect.fish
#
# Ignore list: REXURRECT_IGNORE (a fish list). Defaults are set only if it
# is unset. conf.d runs before config.fish, so in config.fish:
#   set -a REXURRECT_IGNORE htop tig   # extend
#   set -g REXURRECT_IGNORE ls cd      # replace
#   set -g REXURRECT_IGNORE            # ignore nothing

status is-interactive; or return 0
set -q REX_BLOCK; and test -n "$REX_BLOCK"; or return 0
# REX_BLOCK names a file: never let it point outside the recorder directory.
string match -qr '^[[:alnum:]:_-][[:alnum:]:._-]*$' -- $REX_BLOCK; or return 0

# Nested shell (nix develop, a fish started by hand): the outermost shell in
# this block already claimed it under another PID. `exec fish` keeps the PID.
# Compatible with the zsh recorder, which uses the same variable.
if string match -q -- "* $REX_BLOCK" "$_REXURRECT_RECORDER"
    and test "$_REXURRECT_RECORDER" != "$fish_pid $REX_BLOCK"
    return 0
end
set -gx _REXURRECT_RECORDER "$fish_pid $REX_BLOCK"

set -q REXURRECT_IGNORE
or set -g REXURRECT_IGNORE ls ll la l cd pushd popd pwd clear reset exit rexurrect

function _rexurrect_dir
    if test -n "$REXURRECT_STATE_DIR"
        echo $REXURRECT_STATE_DIR/recorder
    else if string match -q '/*' -- "$XDG_STATE_HOME"
        echo $XDG_STATE_HOME/rexurrect/recorder
    else if test -n "$HOME"
        echo $HOME/.local/state/rexurrect/recorder
    else
        return 1
    end
end

# Whether command line $argv[1] is a single command whose name (as typed, or
# the last part of its path) is on the ignore list. Anything joined with
# ; & | (which covers `; and`, `&&`, `||`, pipes) counts as not ignored.
function _rexurrect_ignored
    string match -qr '[;&|]' -- $argv[1]; and return 1
    set -l words (string split -n ' ' -- (string trim -- $argv[1]))
    test (count $words) -gt 0; or return 1
    set -l name $words[1]
    contains -- $name $REXURRECT_IGNORE
    or contains -- (string replace -r '.*/' '' -- $name) $REXURRECT_IGNORE
end

function _rexurrect_write -a dir cmd
    set -l file $dir/$REX_BLOCK
    set -l tmp $dir/.$REX_BLOCK.$fish_pid
    if not test -d $dir
        command mkdir -p -m 700 $dir 2>/dev/null; or return 0
    end
    printf '%s\n' $cmd >$tmp 2>/dev/null; or return 0
    command mv -f $tmp $file 2>/dev/null
end

# Record as a command starts, so a program still running at save time counts.
function _rexurrect_record --on-event fish_preexec
    set -l cmd $argv[1]
    test -n "$cmd"; or return 0
    # Any control character (newline, tab) would misbehave when typed back.
    string match -qr '[[:cntrl:]]' -- $cmd; and return 0
    _rexurrect_ignored $cmd; and return 0
    set -l dir (_rexurrect_dir); or return 0
    _rexurrect_write $dir $cmd
end

# Rewrite the existing record as the prompt returns, so its mtime tells
# rexurrect the shell regained control (the program it saw had exited).
# Never creates a record.
function _rexurrect_rewrite --on-event fish_prompt
    set -l dir (_rexurrect_dir); or return 0
    set -l file $dir/$REX_BLOCK
    test -f $file; or return 0
    read -l record <$file 2>/dev/null; or return 0
    _rexurrect_write $dir $record
end
