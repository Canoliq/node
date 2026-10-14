# canoLiq node

Docker setup for running a **canoLiq (chain 29)** node on Canopy mainnet, as a
full node or as a committee validator.

Narrative docs live at <https://docs.canoliq.org>. This repo is the working
reference: clone it and the config is already correct, so there is nothing to
transcribe.

> [!IMPORTANT]
> **This is a second node.** A canopy node serves exactly one chain — `chainId`
> is a single value, not a list — so chain 29 runs *alongside* your chain-1
> node, not instead of it. Same `validator_key.json`, separate data directory,
> separate port. One key legitimately validates both chains.
>
> Never run two chain-29 nodes with the same key. That is a double-sign.

## Prerequisites

- A server with `docker`
- Inbound **TCP 9029** open (host firewall *and* cloud/provider firewall)
- A publicly reachable hostname that resolves **directly** to the server (see Ports)
- A **chain-1 RPC** to use as the root chain. `config.json` ships with Canopy's public one; your own chain-1 node is better if you run one

## 1. Run the node

**1. Clone**

```bash
git clone https://github.com/Canoliq/node.git canoliq-node
cd canoliq-node
```

**2. Create `.env` and set `DOMAIN`** to your server's public hostname. On the
same server as a chain-1 node, use the same `DOMAIN` as that node; the two are
told apart by port (9001 vs 9029).

```bash
cp .env.example .env
```

**3. Key.** Pick one; don't paste this blindly.

- **Full node:** `make gen-key` creates a fresh `config/validator_key.json` and
  `config/keystore.json`.
- **Validator:** copy your chain-1 validator's `validator_key.json` and
  `keystore.json` into `config/` instead. Never run two chain-29 nodes with the
  same key.

**4. Root chain.** `rootChain` in `config/config.json` defaults to Canopy's
public chain-1 RPC, so there is nothing to change unless a chain-1 node runs on
this server. See "On rootChain" below.

**5. Optional: snapshot.** `make snapshot` restores the latest chain-29
snapshot (~800 MB) instead of syncing from genesis (~25 minutes).

**6. Start**

```bash
make node-up                   # public root chain
make node-up-local-rootchain   # chain-1 node on this server (see "On rootChain")
```

> [!IMPORTANT]
> **`DOMAIN` in `.env` overrides `externalAddress` in `config.json`.** The
> compose runs `start --external-address ${DOMAIN:-localhost}`, and that flag
> wins. Set `DOMAIN` as well, or the node advertises `localhost` and no peer
> can reach it — while `config.json` still looks correct.

> [!NOTE]
> **Upgrading from an earlier version of this repo?** The compose service was
> renamed from `node` to `canoliq-node` (the container name is unchanged). After
> `git pull`, recreate it once:
> `docker compose down && docker compose up -d`. Chain data in `./data` is kept.
> Validators: the node is offline for a few seconds, so expect to miss at most
> a block or two.
>
> - If you edited `config/config.json`, `git pull` may refuse to overwrite it:
>   `git stash && git pull && git stash pop`, then keep your own `rootChain`.
> - If you uncommented the `networks` blocks in `docker-compose.yml` from the
>   previous version, revert them (`git checkout docker-compose.yml`) and use
>   `make node-up-local-rootchain` instead.

**On `rootChain`.** Chain 29 follows chain 1, so the node needs the RPC
(port 50002) of a **chain-1** node, as reachable from inside this container.

- **Default:** `config.json` points at Canopy's public chain-1 RPC
  (`https://root.net.app.canopynetwork.org`). It works out of the box, with no
  Docker networking.
- **Your own chain-1 node** is better if you run one: lower latency and one less
  third party in your consensus path.
  - **On another server** (for example, your consensus validator): use
    `http://<chain-1-host>:50002`, and allow only this server's IP on that port.
  - **On the same server** (the standard `canopy-network/node` compose, run
    as-is): start with `make node-up-local-rootchain`, which adds
    `docker-compose.rootchain-local.yml` and joins the chain-1 node's Docker
    network, then use `"url": "http://node:50002"`. If you cloned the chain-1
    repo into a folder other than `node`, set `ROOT_CHAIN_NETWORK` in `.env`
    (`docker network ls` shows the name).
- **The URL must be scheme, host and port only.** No path and no trailing
  slash: the node builds its websocket URL from the host and drops the path, so
  a URL ending in `/rpc` connects and then fails every subscription with
  `Empty root chain info` / `not subscribed`, which looks like a peering fault.

> [!NOTE]
> **Monitoring on a shared host.** `docker-compose.monitoring.yml` uses the same
> container names (`caddy`, `prometheus`, `grafana`, ...) and host ports 80/443
> as the chain-1 repo's monitoring stack, so only one of the two can run on a
> machine. If chain-1 monitoring is already up, start just the node
> (`make node-up` or `make node-up-local-rootchain`).

## 2. Verify — before you stake

Do not skip these. Each one catches a failure that is invisible from the
outside — a node can look perfectly healthy and still be wrong.

```bash
# 1. syncing, and reaches the current tip
docker exec canoliq-node wget -qO- --post-data='{}' \
  --header='Content-Type: application/json' \
  http://127.0.0.1:50002/v1/query/height

# 2. the plugin is in canoliq mode, not the base-SDK tutorial
docker exec canoliq-node head -2 /tmp/plugin/go-plugin.log
#    want: starting plugin in 'canoliq' mode (liquid staking)

# 3. canoLiq genesis replayed and state matches the network
docker exec canoliq-node wget -qO- http://127.0.0.1:8587/v1/health
#    want: "genesisComplete": true, "chainId": 29
#    compare canopyTotalStake / tvlCapUcnpyEffective against a known-good node --
#    equal values prove you computed the SAME state, not merely that you
#    stopped erroring. Height alone does not prove this.

# 4. your P2P port is reachable FROM OUTSIDE (run this somewhere else)
nc -z <your-host> 9029
```

If height stays at **0** and the plugin health shows `"genesisComplete": false`,
the node isn't following chain 1. Check `rootChain` first (see above):
`docker logs canoliq-node 2>&1 | grep -i root | tail`.

If height sticks at **4679** with `unequal block hash` in the logs, your plugin
config is missing or wrong — see "Why the plugin config matters" below.

If height sticks at **2** with `unequal block hash` (a different `stateRoot`),
`config.json` is missing chain 29's emission parameters (`initialTokensPerBlock`,
`blocksPerHalvening`). Without them the node mints chain 1's default reward
every block and diverges immediately. Use this repo's `config.json` as-is.

If the container restart-loops with `canopy binary not found` after you wiped
`data/`, recreate it: `docker compose up -d --force-recreate canoliq-node`. The image
links `/bin/cli` to a file inside the data directory, and wiping the directory
breaks the link inside the old container.

> [!NOTE]
> **Snapshot.** `make snapshot` restores chain 29's published snapshot from
> `SNAPSHOT_URL` in `.env` (already set). It must be chain 29's: the generic
> canopy-1 snapshot is the root chain's data and would restore the wrong chain.
> Syncing from genesis without it takes about 25 minutes.

## 3. Join the committee — last, not first

> [!TIP]
> Step-by-step version for validators already running chain 1:
> [`docs/JOIN-COMMITTEE.md`](docs/JOIN-COMMITTEE.md)


Only once all four checks pass, add committee `29` to your existing chain-1
validator with an edit-stake. No new key, no unstaking; it is one field.

> [!WARNING]
> **The edit-stake takes effect immediately, at your full stake weight.** There
> is no grace period and no check that your node is actually running or
> reachable. If you hold a meaningful share of the committee and are not
> serving, the chain stops the first time you are elected proposer.
>
> Set the validator address to the **same dialable host** your node advertises.

**Prefer delegating if you do not want to operate a node.** Delegates count
toward the committee's stake but never enter the validator set, so they cannot
affect liveness and need no node at all.

## Why the plugin config matters

canoLiq is a plugin on top of canopy. `config.json` must load it:
`"plugin": "go"` starts it, and `pluginAutoUpdate` (`Canoliq/canoliq`) is where the
node downloads it from and keeps it current. canoLiq ships consensus changes as
plugin releases pinned to future heights, so a node without auto-update falls
off the chain at the next activation height.

Two files in `config/canoliq/` are **consensus-critical**:

| | |
|---|---|
| `genesis.mainnet.json` | canoLiq's genesis state. Must be byte-identical everywhere. |
| `canoliq-config.json` | carries `"activationHeight": 4679` |

`activationHeight` pins the block in which canoLiq genesis is written into
consensus state. Every node must run it in **the same block**. Get it wrong, or
omit the plugin config entirely, and your node computes a different app hash
from block 4679 onward and stalls there permanently with `unequal block hash` —
no amount of resyncing fixes it, because the divergence is in the state machine,
not the chain data.

`redemptionUnstakingBlocks: 30240` is consensus-critical for the same reason.

## Ports

| Port | Purpose |
|---|---|
| **9029** | P2P — `9000 + chainId`. Must be reachable from the internet. |
| 50002 | RPC |
| 50003 | Admin RPC |
| 8587 | canoLiq plugin RPC |

> [!CAUTION]
> **Your advertised address must resolve directly to your node.** P2P is raw
> TCP, so it cannot pass through an HTTP/HTTPS proxy or CDN. If the hostname
> you advertise sits behind one, peers cannot reach you no matter how the node
> itself is configured — point a plain DNS record at the server instead.

## Getting the current committee peers

The dial peer in `config/config.json` is the canoLiq team's validator. To see
the live committee — membership changes on any edit-stake — query the root
chain:

```bash
curl -s -X POST <your-chain-1-rpc>/v1/query/root-chain-info \
  -H 'Content-Type: application/json' -d '{"height":0,"id":29}'
```

Each entry in `validatorSet` gives a `publicKey` and a `netAddress`. A dial peer
is `<publicKey>@<host>` **with no port**. Canopy derives the P2P port by adding
the chain ID to whatever port it is given (`lib.ResolvePort`). With no port it
starts from the default 9000, so chain 29 lands on 9029. Writing `:9029`
explicitly makes it dial 9029 + 29 = **9058**, which nobody listens on.

## Monitoring

`docker-compose.monitoring.yml` adds Prometheus, Loki, Alloy and Grafana.

```bash
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d
```
