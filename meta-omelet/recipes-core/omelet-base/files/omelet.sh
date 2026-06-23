# Omelet shell environment (sourced from /etc/profile.d)
export EDITOR=nano

# Make sure the interactive login shell (which launches opencode) runs in a
# UTF-8 locale, so the TUI emits/handles UTF-8 consistently. Don't clobber a
# locale the user may have set already.
: "${LANG:=C.UTF-8}"
export LANG

# opencode reads provider credentials from the environment.
# Drop your keys in /etc/omelet/api-keys and they get loaded here on login.
if [ -r /etc/omelet/api-keys ]; then
    . /etc/omelet/api-keys
fi
