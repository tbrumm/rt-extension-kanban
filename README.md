# RT-Extension-KANBAN

Adds a Kanban board to [Request Tracker](https://bestpractical.com/request-tracker/) with real-time WebSocket updates, drag-and-drop ticket management, and a fully configurable lane layout.

![Kanban board screenshot](https://raw.githubusercontent.com/nixcloud/rt-extension-kanban/master/screenshots/kanban.jpg)

**Features**

- Real-time updates across all connected browsers via WebSockets — no page reloads
- Drag-and-drop ticket operations with automatic field updates
- Powerful display filters with regular expression support
- Highly configurable lanes with custom queries and drop actions
- Fullscreen mode for large monitors
- Bootstrap 5 / Dark Mode compatible UI (RT 6)

---

## Requirements

| Component | Minimum version |
|-----------|----------------|
| Request Tracker | 6.0.0 |
| Perl | 5.26 |
| Redis | 5.0 (for WebSocket live updates) |
| Mojolicious | 9.0 (for WebSocket server) |
| Mojo::Redis | 3.27 (for WebSocket server) |

---

## Installation

### 1 — Install the extension

```sh
perl Makefile.PL
make
sudo make install
```

The installer copies files into `/opt/rt6/local/plugins/RT-Extension-KANBAN/`.

### 2 — Activate the plugin

Add to `/opt/rt6/etc/RT_SiteConfig.pm`:

```perl
Plugin('RT::Extension::KANBAN');
```

### 3 — Clear the Mason cache and restart

```sh
sudo rm -rf /opt/rt6/var/mason_data/obj/*
sudo systemctl restart apache2    # or nginx / your web server
```

### 4 — Add the Kanban element to a dashboard

In RT → **Tools → Dashboard → Edit** add the **Kanban** element to any dashboard column.

---

## Configuration

Configuration lives in `/opt/rt6/etc/RT_SiteConfig.pm`.

### Defining Kanban boards

```perl
Set( %KanbanConfigs, (
  MyBoard => q(
  {
    "lanes": [
      {
        "Name":   "New / Open",
        "Change": {"Status": "open"},
        "Query":  "(Status='open' OR Status='new')"
      },
      {
        "Name":   "Stalled",
        "Change": {"Status": "stalled"},
        "Query":  "(Status='stalled') AND (Owner='{{=it.CurrentUser}}')"
      },
      {
        "Name":       "Resolved",
        "Change":     {"Status": "resolved"},
        "Query":      "(Status='resolved') AND (LastUpdated > '{{=it.Date}}')",
        "timeOffset": 7
      }
    ]
  })
));
```

Always clear the Mason cache after changing `%KanbanConfigs`.

#### Lane fields

| Field | Required | Description |
|-------|----------|-------------|
| `Name` | yes | Column header text |
| `Query` | yes | RT search query for tickets in this lane. Supports `AND`, `OR`, `NOT`, `=`, `!=`, `<`, `<=`, `>`, `>=` |
| `Change` | no | Ticket fields to update when a ticket is dropped into this lane, e.g. `{"Status": "open"}` |
| `timeOffset` | no | Days subtracted from today when expanding `{{=it.Date}}`. Default: `5` |
| `CallOnEnter` | no | JavaScript function body called on drop; receives `ticket`; must return an array of field names to save |

#### Template variables

| Variable | Replaced with |
|----------|--------------|
| `{{=it.Date}}` | Today's date minus `timeOffset` days (ISO format) |
| `{{=it.CurrentUser}}` | The logged-in RT username |

### Limiting boards per user

```perl
# Available to all users by default
Set(@KanbanDefault, "MyBoard", "OtherBoard");

# Override for a specific user (replaces @KanbanDefault for that user)
Set(@Kanban_alice, "MyBoard");
```

### Read-only mode per user

```perl
Set($KanbanReadOnly_alice, 1);
```

### Truncate long creator names

```perl
Set($cutCreatorName, 12);   # default: 10
```

---

## WebSocket Live Updates

The WebSocket server (`bin/rt-kanban-websocket`) subscribes to a Redis pub/sub channel and pushes ticket-update events to all connected browser tabs in real time.

### How it works

```
RT (Perl) ──publishes ticket ID──► Redis channel "rt-ticket-activity"
                                        │
                          rt-kanban-websocket (Mojolicious)
                                        │
                    ◄── JSON push ──────┴──── all connected browsers
```

RT publishes a ticket ID to Redis whenever a ticket changes. The WebSocket server debounces rapid successive events (200 ms window), then broadcasts `{ "updateTicket": { "id": "42", "sequence": N } }` to every authenticated client. Each browser tab fetches the updated ticket data via REST 2.0 and re-renders only the affected card.

### Prerequisites

Install the required Perl modules:

```sh
sudo cpanm Mojolicious Mojo::Redis
# or
sudo cpanm --installdeps /opt/rt6/local/plugins/RT-Extension-KANBAN/
```

Redis must be running and accessible:

```sh
sudo systemctl enable --now redis
redis-cli ping   # should return PONG
```

### Configure the WebSocket server

Copy and edit the configuration file:

```sh
sudo cp /opt/rt6/local/plugins/RT-Extension-KANBAN/etc/rt-kanban-websocket.conf \
        /opt/rt6/local/plugins/RT-Extension-KANBAN/etc/rt-kanban-websocket.conf
```

Edit `/opt/rt6/local/plugins/RT-Extension-KANBAN/etc/rt-kanban-websocket.conf`:

```perl
{
  # Redis connection URL
  redis_url => 'redis://localhost',

  # Pub/sub channel — must match the channel in KANBAN.pm
  channel   => 'rt-ticket-activity',

  # Base URL of your RT instance (no trailing slash)
  rt_url    => 'https://rt.example.com',

  # Cookie domain — must match your RT domain
  rt_domain => 'rt.example.com',

  rt_path   => '/',

  # REST 2.0 endpoint used to validate session cookies.
  # Any ticket that exists works; use ticket 1 or another permanent ticket.
  auth_probe_url => 'https://rt.example.com/REST/2.0/ticket/1',

  log_level => 'info',   # debug | info | warn | error | fatal
}
```

### Install and start the systemd service

```sh
sudo cp /opt/rt6/local/plugins/RT-Extension-KANBAN/etc/rt-kanban-websocket.service \
        /etc/systemd/system/rt-kanban-websocket.service

sudo systemctl daemon-reload
sudo systemctl enable --now rt-kanban-websocket

# Verify
sudo systemctl status rt-kanban-websocket
journalctl -u rt-kanban-websocket -f
```

The service runs as `www-data` on port **5000** by default. Adjust `User`, `Group`, and the `-l http://*:5000` listen address in the service file to match your environment.

### Reverse proxy setup (recommended)

Expose the WebSocket server under the same origin as RT so the browser can connect without CORS issues and the session cookie is forwarded automatically.

#### Nginx

```nginx
server {
    listen 443 ssl;
    server_name rt.example.com;

    # ... your SSL certificate directives ...

    # RT application
    location / {
        proxy_pass         http://127.0.0.1:8080;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }

    # WebSocket server — same origin, different path
    location /websocket {
        proxy_pass             http://127.0.0.1:5000;
        proxy_http_version     1.1;
        proxy_set_header       Upgrade    $http_upgrade;
        proxy_set_header       Connection "upgrade";
        proxy_set_header       Host       $host;
        proxy_set_header       X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_read_timeout     600s;
        proxy_send_timeout     600s;
    }
}
```

#### Apache (mod_proxy_wstunnel)

```apache
<VirtualHost *:443>
    ServerName rt.example.com

    # ... SSL directives ...

    # RT application
    ProxyPass        /  http://127.0.0.1:8080/
    ProxyPassReverse /  http://127.0.0.1:8080/

    # WebSocket server
    ProxyPass        /websocket  ws://127.0.0.1:5000/websocket
    ProxyPassReverse /websocket  ws://127.0.0.1:5000/websocket
</VirtualHost>

# Required modules: mod_proxy, mod_proxy_http, mod_proxy_wstunnel
```

With a reverse proxy in place the Kanban JavaScript connects to `wss://rt.example.com/websocket` automatically — no extra RT configuration is needed.

### Without a reverse proxy (alternative)

If you run the WebSocket server on a different port without a reverse proxy, tell RT which port to use:

```perl
# /opt/rt6/etc/RT_SiteConfig.pm
Set($WebsocketPort, "5000");
```

The Kanban JavaScript will then connect to `wss://rt.example.com:5000/websocket`.  
Both RT and the WebSocket server **must** be on the same domain so the browser forwards the session cookie.

Clear the Mason cache after any change to `$WebsocketPort`.

### Quick test

After starting the service, open the debug console in a browser while logged in to RT:

```
https://rt.example.com/websocket
```

The page shows a live WebSocket connection log with all incoming events.

---

## How RT publishes ticket changes

The extension hooks into RT's callback system. Whenever a ticket is created or updated, RT publishes the ticket ID to the configured Redis channel. No changes to RT core are required — the hook lives in:

```
local/plugins/RT-Extension-KANBAN/lib/RT/Extension/KANBAN.pm
```

---

## Author

- Paul Seitz <paul.m.seitz@gmail.com>
- Joachim Schiele <js@lastlog.de>

## Bugs

Please report bugs at <https://github.com/nixcloud/rt-extension-kanban/issues>.

## Thanks

- [LiHAS Stuttgart](http://www.lihas.de/) for sponsoring this work
- [Bob Cravens](http://bobcravens.com/) for his original Kanban example
- Christian Loos <cloos@netcologne.de>, Shawn Moore, Jim Brandt — for RT guidance

## License

Copyright (c) 2016 Joachim Schiele / Paul Seitz.  
Licensed under the **GNU General Public License, Version 2** (GPL-2.0).
