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
- A **chain-1 RPC** to use as the root chain — your own chain-1 node, or a public one

## 1. Run the node

```bash
git clone https://github.com/Canoliq/node.git canoliq-node
cd canoliq-node

# generate config/keystore.json + config/validator_key.json
make gen-key

# fill in the two placeholders in config/config.json:
#   "rootChain": [{ "chainId": 1, "url": "<your-chain-1-rpc>" }]
#   "externalAddress": "tcp://<your-public-host>"     (validators must be dialable)

docker compose up -d
```

> [!IMPORTANT]
> **`DOMAIN` in `.env` overrides `externalAddress` in `config.json`.** The
> compose runs `start --external-address ${DOMAIN:-localhost}`, and that flag
> wins. Set `DOMAIN` as well, or the node advertises `localhost` and no peer
> can reach it — while `config.json` still looks correct.

**On `rootChain`.** Chain 29 follows chain 1, so the node needs a chain-1 RPC.
If you already run a chain-1 node on this box — most committee members do —
point it there over the local docker network (e.g.
`http://node:50002`); it is lower latency than a public endpoint and one less
third party in your consensus path. Otherwise use any chain-1 RPC you trust.

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

If height sticks at **4679** with `unequal block hash` in the logs, your plugin
config is missing or wrong — see "Why the plugin config matters" below.

If height sticks at **2** with `unequal block hash` (a different `stateRoot`),
`config.json` is missing chain 29's emission parameters (`initialTokensPerBlock`,
`blocksPerHalvening`). Without them the node mints chain 1's default reward
every block and diverges immediately. Use this repo's `config.json` as-is.

If the container restart-loops with `canopy binary not found` after you wiped
`data/`, recreate it: `docker compose up -d --force-recreate node`. The image
links `/bin/cli` to a file inside the data directory, and wiping the directory
breaks the link inside the old container.

> [!NOTE]
> **There is no snapshot, and you do not need one.** Chain 29 is young, so a
> node syncs from genesis to the tip in roughly twenty minutes. (The snapshot
> tooling this repo inherited was for chain-1 mainnet archives and has been
> removed — restoring one here would give you the wrong chain's data.)

## 3. Join the committee — last, not first

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
