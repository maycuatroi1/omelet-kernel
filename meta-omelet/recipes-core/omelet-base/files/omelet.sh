# Omelet shell environment (sourced from /etc/profile.d)
export EDITOR=nano

# opencode reads provider credentials from the environment.
# Drop your keys in /etc/omelet/api-keys and they get loaded here on login.
if [ -r /etc/omelet/api-keys ]; then
    . /etc/omelet/api-keys
fi
