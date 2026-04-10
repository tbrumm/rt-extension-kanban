# cpanfile — Perl module dependencies for RT-Extension-KANBAN
#
# Install all dependencies:
#   cpanm --installdeps .
#
# Or individually:
#   cpanm Mojolicious Mojo::Redis

# Core RT extension — no extra CPAN modules needed beyond RT itself.

# WebSocket server (bin/rt-kanban-websocket)
requires 'Mojolicious', '>= 9.0';
requires 'Mojo::Redis',  '>= 3.27';
