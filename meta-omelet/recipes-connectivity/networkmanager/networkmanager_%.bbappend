# Omelet: enable the nmtui ncurses front-end (not in the default PACKAGECONFIG).
# Gives a ready-made friendly TUI alongside our `wifi` wrapper. Pulls in libnewt.
PACKAGECONFIG:append = " nmtui"
