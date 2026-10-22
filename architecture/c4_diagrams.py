"""Generate mcl-search's two C4 diagrams into assets/.

Run:  python3 architecture/c4_diagrams.py

  c4-context.svg     Level 1: what the service talks to
  c4-components.svg  Level 2: what it is made of

Drawn from the code, never from a template: the callbacks and the one gated
capability in mcl_search_service.erl, the member policy in
web_search_member_gate.erl, the responder and its SearXNG calls in
web_search_responder.erl, the dependencies in rebar.config, the port in the
Containerfile and the variables in deploy/docker-compose.yml. When one of those
changes, the diagram changes in the same commit.

Colours are plain classes with a prefers-color-scheme: dark block, no CSS custom
properties (rsvg-convert renders those black), so the SVGs render the same on
GitHub, in IDE previews and through rsvg-convert. After a change, render each
(rsvg-convert -w 1400 assets/c4-context.svg -o /tmp/c.png) and look at it; keep
architecture/README.md's tables in step.
"""
import os
from xml.sax.saxutils import escape

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets")

SANS = '"Atkinson Hyperlegible", "Segoe UI", system-ui, -apple-system, Helvetica, Arial, sans-serif'
MONO = '"JetBrains Mono", ui-monospace, Menlo, Consolas, monospace'

# Element kinds, each (light fill, light stroke, dark fill, dark stroke).
KINDS = {
    "b-sys": ("#F5E9CC", "#A56F0A", "#3A2E13", "#E3AA3C"),   # in scope
    "b-per": ("#E3EBF2", "#3B5B7A", "#1D2A36", "#8EB4D8"),   # person
    "b-mac": ("#E6E4EE", "#5E5A78", "#26243A", "#A9A4C8"),   # Macula infrastructure
    "b-ext": ("#ECEFED", "#8A9791", "#1C2421", "#7D8B85"),   # external system
    "b-cmp": ("#FFFFFF", "#8A9791", "#171F1C", "#7D8B85"),   # component or container
}

STYLE = f"""<style>
.t-name {{ font-family: {SANS}; font-size: 15px; font-weight: 700; }}
.t-desc {{ font-family: {SANS}; font-size: 12.5px; }}
.t-rel {{ font-family: {SANS}; font-size: 11.5px; paint-order: stroke; stroke-width: 4px; stroke-linejoin: round; }}
.t-code {{ font-family: {MONO}; font-size: 13px; font-weight: 600; }}
.t-type {{ font-family: {MONO}; font-size: 11.5px; }}
.t-bound {{ font-family: {MONO}; font-size: 12px; font-weight: 600; }}
.t-leg {{ font-family: {SANS}; font-size: 12px; }}
.edge {{ fill: none; stroke-width: 1.25; }}
.edge-later {{ fill: none; stroke-width: 1.25; stroke-dasharray: 5 4; }}
.bg {{ fill: #FFFFFF; }}
""" + "".join(f".{k} {{ fill: {v[0]}; stroke: {v[1]}; stroke-width: {2 if k == 'b-sys' else 1.25}; }}\n" for k, v in KINDS.items()) + """\
.b-later { fill: none; stroke: #8A9791; stroke-width: 1.25; stroke-dasharray: 5 4; }
.bound { fill: none; stroke: #B3BDB8; stroke-width: 1; }
.head { fill: #3B5B7A; }
.t-name, .t-code { fill: #16201D; }
.t-type, .t-bound, .t-leg { fill: #66736E; }
.t-desc { fill: #34413C; }
.t-rel { fill: #66736E; stroke: #FFFFFF; }
.edge, .edge-later { stroke: #8A9791; }
.arrowhead { fill: #8A9791; }
@media (prefers-color-scheme: dark) {
.bg { fill: #171F1C; }
""" + "".join(f".{k} {{ fill: {v[2]}; stroke: {v[3]}; }}\n" for k, v in KINDS.items()) + """\
.b-later { stroke: #7D8B85; }
.bound { stroke: #4A5752; }
.head { fill: #8EB4D8; }
.t-name, .t-code { fill: #E6ECE9; }
.t-type, .t-bound, .t-leg { fill: #93A09A; }
.t-desc { fill: #C3CDC8; }
.t-rel { fill: #93A09A; stroke: #171F1C; }
.edge, .edge-later { stroke: #7D8B85; }
.arrowhead { fill: #7D8B85; }
}
</style>"""

DEFS = ('<defs><marker id="a" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
        'orient="auto-start-reverse"><path class="arrowhead" d="M0 0L10 5L0 10z"/></marker></defs>')

LEGEND = [("b-sys", "In scope"), ("b-per", "Person"), ("b-mac", "Macula infrastructure"),
          ("b-ext", "External system"), ("b-cmp", "Container or component")]
BOUNDARY = ("bound", "Boundary")


class Diagram:
    def __init__(self, name, title, w, h):
        self.name, self.title, self.w, self.h, self.parts = name, title, w, h, []

    def text(self, cls, x, y, s, anchor=None, rotate=None):
        a = f' text-anchor="{anchor}"' if anchor else ""
        r = f' transform="rotate({rotate} {x} {y})"' if rotate is not None else ""
        self.parts.append(f'<text class="{cls}" x="{x}" y="{y}"{a}{r}>{escape(s)}</text>')

    def box(self, cls, x, y, w, h, name, kind, desc, person=False, code=False):
        # A box that is too small for its own words renders as text on top of the
        # next box, which no test would catch and a reader would read as the
        # diagram saying something it does not. Fail here instead.
        need = 70 + 16 * max(len(desc) - 1, 0) + 18
        if h < need:
            raise ValueError(f"{self.name}: {name} needs height {need}, has {h}")
        for line in desc:
            if 16 + 6.2 * len(line) > w - 16:
                raise ValueError(f"{self.name}: {name}: '{line}' is wider than {w - 32}px")
        self.parts.append(f'<rect class="{cls}" x="{x}" y="{y}" width="{w}" height="{h}" rx="10"/>')
        tx = x + 16
        if person:
            self.parts.append(f'<circle class="head" cx="{x + 26}" cy="{y + 24}" r="9"/>')
            tx = x + 44
        self.text("t-code" if code else "t-name", tx, y + 28, name)
        self.text("t-type", tx, y + 46, kind)
        for i, line in enumerate(desc):
            self.text("t-desc", x + 16, y + 70 + 16 * i, line)

    def bound(self, x, y, w, h, label):
        self.parts.append(f'<rect class="bound" x="{x}" y="{y}" width="{w}" height="{h}" rx="12"/>')
        self.text("t-bound", x + 16, y + 22, label)

    def edge(self, d, later=False):
        self.parts.append(f'<path class="{"edge-later" if later else "edge"}" d="{d}" marker-end="url(#a)"/>')

    def legend(self, y, boundary=True):
        x = 24
        for cls, label in LEGEND + ([BOUNDARY] if boundary else []):
            self.parts.append(f'<rect class="{cls}" x="{x}" y="{y}" width="22" height="14" rx="3"/>')
            self.text("t-leg", x + 30, y + 12, label)
            x += 34 + 6.6 * len(label)

    def write(self):
        svg = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {self.w} {self.h}" role="img" '
               f'aria-label="{escape(self.title)}">', f"<title>{escape(self.title)}</title>", STYLE, DEFS,
               f'<rect class="bg" x="0" y="0" width="{self.w}" height="{self.h}"/>'] + self.parts + ["</svg>", ""]
        with open(os.path.join(OUT, self.name), "w") as f:
            f.write("\n".join(svg))


def context():
    d = Diagram("c4-context.svg", "mcl-search system context", 1000, 700)
    d.box("b-per", 60, 30, 280, 104, "Realm member", "[Person or AI agent]",
          ["A node on the mesh holding a", "realm-signed member token"], person=True)
    d.box("b-per", 660, 30, 280, 104, "Service operator", "[Person]",
          ["Runs the node beside SearXNG and", "supplies the realm, key, stations"], person=True)
    d.box("b-sys", 360, 200, 280, 150, "mcl-search", "[mcl_om mesh service, own box]",
          ["One procedure, mcl-search/web_search,", "served only to email-verified realm",
           "members; /health on loopback 8497. It", "keeps no store and no search history"])
    d.box("b-mac", 60, 420, 280, 136, "macula-realm", "[Macula infrastructure]",
          ["Signs the member token macula checks", "before a call reaches the handler;",
           "its D25 grant names", "mcl-search/web_search"])
    d.box("b-mac", 360, 420, 280, 120, "Macula stations, mesh DHT", "[Macula infrastructure]",
          ["The pinned stations are the", "service's entry points (QUIC); the", "DHT takes its advertisement"])
    d.box("b-ext", 660, 420, 280, 136, "SearXNG", "[External system, unmodified]",
          ["JSON search API and /healthz on", "the same host, 127.0.0.1:8888. It",
           "queries the upstream engines; this", "service talks to nothing else"])
    d.edge("M200 134V178H450V200")
    d.text("t-rel", 208, 152, "calls mcl-search/web_search,")
    d.text("t-rel", 208, 166, "with a member token")
    d.edge("M800 134V178H550V200")
    d.text("t-rel", 690, 166, "deploys; sets SEARXNG_URL")
    d.edge("M430 350V380H200V420"); d.text("t-rel", 240, 372, "boot claim, D25 grant")
    d.edge("M500 350V420"); d.text("t-rel", 508, 404, "advertises mcl-search/web_search")
    d.edge("M570 350V390H800V420")
    d.text("t-rel", 578, 366, "GET /search?format=json;")
    d.text("t-rel", 578, 382, "GET /healthz for health")
    d.text("t-desc", 40, 600, "SearXNG reaches the live web; this service reaches only SearXNG, on loopback, and keeps no")
    d.text("t-desc", 40, 618, "record of a query. A caller without a member token is refused by macula before the handler runs.")
    d.legend(660, boundary=False)
    d.write()


def components():
    d = Diagram("c4-components.svg", "mcl-search components", 1000, 960)
    d.bound(16, 40, 968, 660, "mcl-search [Container]")
    d.box("b-cmp", 32, 70, 456, 120, "mcl_search_service", "[mcl_om_service behaviour]",
          ["The six callbacks mcl_om resolves by name at", "startup. One capability, web_search, whose auth",
           "is web_search_member_gate:policy/0"], code=True)
    d.box("b-cmp", 512, 70, 456, 104, "mcl_search_app", "[OTP application]",
          ["mcl_om:boot/1 wires the mesh, the realm", "identity and /health, then starts the service"], code=True)
    d.box("b-sys", 32, 214, 456, 120, "web_search_member_gate", "[capability auth policy]",
          ["Builds the realm_member_required policy from", "MCL_REALM_KEY: its key id and the tier",
           "member/email-verified. No open fallback"], code=True)
    d.box("b-cmp", 512, 214, 456, 104, "mcl_search_sup", "[supervisor, one_for_one]",
          ["No children: macula_response spawns a", "responder per call, and nothing is kept"], code=True)
    d.box("b-sys", 32, 378, 928, 140, "web_search_responder", "[macula_response handler]",
          ["handle_request/2: query 1 to 512 bytes, limit 1 to 25",
           "default 10. GET SearXNG /search?format=json with a",
           "20 s timeout; replies title, url, content and engine",
           "as text. probe /healthz for health, never a search"], code=True)
    d.box("b-mac", 32, 542, 456, 120, "mcl_om", "[library, ~> 1.4]",
          ["boot/1: loads the node identity key, joins the", "realm, opens the QUIC pool through the pinned",
           "stations, registers web_search, serves /health on 8497"], code=True)
    d.box("b-mac", 512, 542, 456, 120, "macula SDK", "[library, ~> 16.0, wire 1.0]",
          ["QUIC transport, the member token macula checks", "before a call reaches the handler, RPC dispatch",
           "to a provider that answers by name, DHT records"], code=True)
    d.box("b-ext", 40, 728, 920, 104, "SEARXNG_URL, MCL_REALM, MCL_REALM_KEY, MACULA_STATION_SEEDS, MACULA_STATION_NODE_IDS",
          "[host environment; identity key at /etc/mcl/secrets/identity.key]",
          ["MCL_HEALTH_PORT 8497 is the /health port, loopback only. SEARXNG_URL has no default: without it the",
           "service refuses to start. MCL_SERVICE_NAME and MCL_BOX label the boot claim."], code=True)
    d.edge("M512 130H488"); d.text("t-rel", 482, 122, "starts", anchor="end")
    d.edge("M200 190V214"); d.text("t-rel", 208, 206, "capabilities/0 takes its auth from")
    d.edge("M488 160H500V360H260V378"); d.text("t-rel", 300, 352, "declares its handler")
    d.edge("M200 518V542"); d.text("t-rel", 208, 534, "reads the payload, mcl_om_wire")
    d.edge("M740 518V542"); d.text("t-rel", 748, 534, "dispatched and replied through")
    d.edge("M488 602H512"); d.text("t-rel", 482, 592, "uses", anchor="end")
    d.edge("M32 130H20V602H32"); d.text("t-rel", 26, 400, "resolved by name at boot", anchor="middle", rotate=-90)
    d.edge("M160 662V728"); d.text("t-rel", 168, 690, "reads the identity key")
    d.text("t-desc", 40, 866, "config/sys.config.src fixes the org, mcl-search, which prefixes the procedure and the D25 grant, and pins")
    d.text("t-desc", 40, 884, "the realm key. There is no store, so the service mounts one volume,")
    d.text("t-desc", 40, 902, "/etc/mcl/secrets, and nothing else. Its JSON and HTTP are stdlib (json, httpc): no other dependency.")
    d.legend(930, boundary=False)
    d.write()


if __name__ == "__main__":
    for make in (context, components):
        make()
