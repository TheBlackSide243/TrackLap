# The real circuits the screenshot workflow puts in the app (screenshots/tracks.json), in the app's
# Track JSON: the main loop and the pit lane from OpenStreetMap, a start line beside the middle of the
# pit lane in the race direction (pit lanes are mapped one way, the racing way) and two
# intermediates at a third and two thirds of the lap.
#   python tools/showcase-tracks.py screenshots/tracks.json
# Track data (c) OpenStreetMap contributors, ODbL.
import xml.etree.ElementTree as ET, math, collections, json, sys, urllib.request

# key, name, place, official length (m), ways that are not the main loop, track id, box (S, W, N, E)
CIRCUITS = [
    ("mugello", "Autodromo del Mugello", "Scarperia e San Piero", 5245, ["Pit", "Mugellino"],
     "5E0C2C61-7D0B-4E8F-9A3B-6A3C1D1F0001", (43.98993, 11.36338, 44.00923, 11.37994)),
    ("monza", "Autodromo Nazionale Monza", "Monza", 5793, ["Pit", "anello", "Sopraelevata", "Pirelli", "Junior"],
     "5E0C2C61-7D0B-4E8F-9A3B-6A3C1D1F0002", (45.6080, 9.2740, 45.6330, 9.2970)),
    ("imola", "Autodromo Enzo e Dino Ferrari", "Imola", 4909, ["Pit"],
     "5E0C2C61-7D0B-4E8F-9A3B-6A3C1D1F0003", (44.33570, 11.70096, 44.34631, 11.72613)),
]

def xy(o, p):
    return ((p[1] - o[1]) * 111320 * math.cos(math.radians(o[0])), (p[0] - o[0]) * 111320)

def ll(o, v):
    return (o[0] + v[1] / 111320, o[1] + v[0] / (111320 * math.cos(math.radians(o[0]))))

def dist(a, b):
    x, y = xy(a, b)
    return math.hypot(x, y)

def load(box):
    s, w, n, e = box
    pad = 0.002
    url = f"https://api.openstreetmap.org/api/0.6/map?bbox={w - pad},{s - pad},{e + pad},{n + pad}"
    req = urllib.request.Request(url, headers={"User-Agent": "TrackLap showcase-tracks"})
    root = ET.fromstring(urllib.request.urlopen(req, timeout=90).read())
    nodes = {n.get("id"): (float(n.get("lat")), float(n.get("lon"))) for n in root.iter("node")}
    ways = []
    for w in root.iter("way"):
        tags = {t.get("k"): t.get("v") for t in w.iter("tag")}
        if tags.get("highway") == "raceway":
            ways.append((tags, [r.get("ref") for r in w.iter("nd") if r.get("ref") in nodes]))
    return nodes, ways

def main_loop(nodes, ways, exclude, official):
    adj = collections.defaultdict(set)
    for tags, refs in ways:
        if any(x.lower() in tags.get("name", "").lower() for x in exclude):
            continue
        for a, b in zip(refs, refs[1:]):
            if a != b:
                adj[a].add(b); adj[b].add(a)
    changed = True
    while changed:
        changed = False
        for n in list(adj):
            if len(adj[n]) <= 1:
                for m in adj[n]: adj[m].discard(n)
                del adj[n]; changed = True
    # What is left after trimming the dead ends is loops. Without junctions each loop is its own
    # cycle; with them (alternative chicanes), the chains between junctions are put together into
    # every simple cycle. The cycle closest to the official length is the circuit.
    branch = {n for n in adj if len(adj[n]) != 2}
    chains, used = [], set()
    for s in branch:
        for m in adj[s]:
            if (s, m) in used: continue
            path = [s, m]
            while path[-1] not in branch:
                nxt = [k for k in adj[path[-1]] if k != path[-2]][0]
                path.append(nxt)
            used.add((path[0], path[1])); used.add((path[-1], path[-2]))
            chains.append(path)
    cycles = []
    if not branch:
        seen = set()
        for s in adj:
            if s in seen: continue
            cyc, prev, cur = [s], None, s
            while True:
                nx = [m for m in adj[cur] if m != prev][0]
                if nx == s: break
                prev, cur = cur, nx; cyc.append(cur)
            seen |= set(cyc); cycles.append(cyc)
    else:
        idx = collections.defaultdict(list)
        for i, c in enumerate(chains): idx[c[0]].append(i); idx[c[-1]].append(i)
        def walk(start, at, used_chains, seq):
            for i in idx[at]:
                if i in used_chains: continue
                c = chains[i] if chains[i][0] == at else chains[i][::-1]
                if c[-1] == start:
                    cycles.append(seq + c[:-1])
                elif c[-1] not in seq:
                    walk(start, c[-1], used_chains | {i}, seq + c[:-1])
        for b in branch: walk(b, b, frozenset(), [])
    def length(c): return sum(dist(nodes[c[i - 1]], nodes[c[i]]) for i in range(len(c)))
    best = min(cycles, key=lambda c: abs(length(c) - official))
    return [nodes[n] for n in best], length(best)

def heading(a, b, o):
    x1, y1 = xy(o, a); x2, y2 = xy(o, b)
    return (x2 - x1, y2 - y1)

def build(key, name, place, official, exclude, tid, box):
    nodes, ways = load(box)
    loop, L = main_loop(nodes, ways, exclude, official)
    pits = [[nodes[r] for r in refs] for tags, refs in ways if "pit" in tags.get("name", "").lower()]
    pit = max(pits, key=lambda p: sum(dist(p[i - 1], p[i]) for i in range(1, len(p))))
    o = loop[0]
    # Start beside the middle of the pit lane.
    pc = [0.0]
    for i in range(1, len(pit)): pc.append(pc[-1] + dist(pit[i - 1], pit[i]))
    j = max(i for i in range(len(pit)) if pc[i] <= pc[-1] / 2)
    f = (pc[-1] / 2 - pc[j]) / ((pc[j + 1] - pc[j]) or 1)
    pm = (pit[j][0] + (pit[j + 1][0] - pit[j][0]) * f, pit[j][1] + (pit[j + 1][1] - pit[j][1]) * f)
    k = min(range(len(loop)), key=lambda i: dist(loop[i], pm))
    loop = loop[k:] + loop[:k]
    # Race direction = the pit lane's way direction (pit lanes are oneway the racing way).
    pd = heading(pit[0], pit[-1], o)
    ld = heading(loop[0], loop[min(15, len(loop) - 1)], o)
    if pd[0] * ld[0] + pd[1] * ld[1] < 0:
        loop = [loop[0]] + loop[1:][::-1]
    cum = [0.0]
    for i in range(1, len(loop)): cum.append(cum[-1] + dist(loop[i - 1], loop[i]))
    total = cum[-1] + dist(loop[-1], loop[0])

    def at(s):
        s %= total
        i = max(j for j in range(len(loop)) if cum[j] <= s)
        a, b = loop[i], loop[(i + 1) % len(loop)]
        seg = dist(a, b); f = (s - cum[i]) / seg if seg else 0
        p = (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f)
        dx, dy = heading(a, b, p)
        n = math.hypot(dx, dy) or 1
        return p, (dx / n, dy / n)

    def gate(s, half=12):
        p, (dx, dy) = at(s)
        px, py = -dy * half, dx * half
        a, b = ll(p, (-px, -py)), ll(p, (px, py))
        return {"a": {"lat": a[0], "lon": a[1]}, "b": {"lat": b[0], "lon": b[1]}}

    coords = lambda pts: [{"lat": p[0], "lon": p[1]} for p in pts]
    lats = [p[0] for p in loop]; lons = [p[1] for p in loop]
    track = {
        "id": tid, "name": name, "place": place,
        "center": {"lat": (min(lats) + max(lats)) / 2, "lon": (min(lons) + max(lons)) / 2},
        "outline": [coords(loop + [loop[0]]), coords(pit)],
        "start": gate(0), "sectors": [gate(total / 3), gate(2 * total / 3)],
        "isDemo": False, "created": 0.0,
    }
    print(f"{key}: loop {total:.0f} m (official {official}), {len(loop)} points, pit {len(pit)} points")
    return track

tracks = [build(*c) for c in CIRCUITS]
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(tracks, f, separators=(",", ":"))
