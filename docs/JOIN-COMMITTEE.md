# Adding Canoliq (chain 29) to your validator

For validators already running a Canopy chain-1 node.

You need a **second node process**. A Canopy node serves one chain — `chainId`
is a single value, not a list — so chain 29 runs alongside your chain-1 node,
using the same validator key.

> [!CAUTION]
> Never run two chain-29 nodes with the same key. That is a double-sign.

## 1. Run the node

```bash
git clone https://github.com/Canoliq/node.git canoliq-node
cd canoliq-node
make gen-key      # or copy your existing config/validator_key.json + keystore.json
```

Set three things:

- `.env` → `DOMAIN=<your-public-host>`
- `config/config.json` → `"rootChain": [{ "chainId": 1, "url": "<your-chain-1-rpc>" }]`
- Open inbound **TCP 9029** (host firewall *and* cloud/provider firewall)

```bash
docker compose up -d
```

> [!IMPORTANT]
> `DOMAIN` overrides `externalAddress` in `config.json` — the compose runs
> `start --external-address ${DOMAIN:-localhost}` and that flag wins. Set it, or
> the node advertises `localhost` and no peer can reach it, while `config.json`
> still looks correct.

Your chain-1 node is the natural root chain: point `rootChain` at it rather
than a public endpoint if it is reachable from this container.

## 2. Verify — before you stake

Syncing from genesis takes roughly 25 minutes. Do not skip these.

```bash
# at the network's tip
docker exec canoliq-node wget -qO- --post-data='{}' \
  --header='Content-Type: application/json' http://127.0.0.1:50002/v1/query/height

# canoLiq genesis replayed and state matches the network
docker exec canoliq-node wget -qO- http://127.0.0.1:8587/v1/health
#   want: "genesisComplete": true, "chainId": 29
```

```bash
# port reachable FROM OUTSIDE -- run this from another machine, not the server
nc -z <your-host> 9029
```

`genesisComplete: true` is the check that matters. Height alone only proves the
node stopped erroring; comparing `canopyTotalStake` against a known-good node
proves it computed the *same state*.

**If height sticks at 2** — `config.json` is missing chain 29's emission
parameters. Use this repo's as-is.

**If height sticks at 4679** — the canoLiq plugin config is missing or wrong.
That block is where canoLiq genesis is written into consensus state; without it
your node computes a different app hash from there onward and can never catch
up, no matter how many times you resync.

## 3. Stake — last, not first

Only once all three checks pass, edit-stake your existing chain-1 validator:

| Field | Value |
|---|---|
| **Committees** | `1,29` |
| **Validator Address** | `tcp://<your-public-host>` — **no port** |

No new key, no unstaking. It is one transaction.

> [!WARNING]
> **Do not add `:9029`.** Canopy adds the chain ID to whatever port you supply
> (`lib.ResolvePort`), so `:9029` resolves to **9058** and nobody listens there.
> With no port it starts from 9000 and derives 9029 correctly. Likewise `:9001`
> becomes 9030.

> [!WARNING]
> **The address must resolve directly to your server.** P2P is raw TCP and
> cannot pass through an HTTP/HTTPS proxy or CDN. If your hostname sits behind
> one, peers cannot reach you however the node is configured.

> [!CAUTION]
> **Stake last.** The edit-stake takes effect immediately at your full stake
> weight, with no check that your node is running or reachable. If you hold a
> meaningful share of the committee and are not serving, the chain halts the
> first time you are elected proposer.
>
> Recovery is a second edit-stake dropping committee 29 — but avoid needing it.

## Just want to participate?

**Delegate instead.** Add the chain ID with `delegate` and you are done: no node
to run, no port to open, no risk to the chain. Delegates count toward the
committee's stake but never enter the validator set, so they cannot affect
liveness.

Validating is only worth the extra steps if you actually want to operate
infrastructure.

## Confirming it worked

```bash
curl -s -X POST <your-chain-1-rpc>/v1/query/root-chain-info \
  -H 'Content-Type: application/json' -d '{"height":0,"id":29}'
```

You should appear in `validatorSet` with your `netAddress`. Within a few blocks
your node's logs should show it being elected and its proposals accepted:

```
Received (H:…, COMMIT) message from proposer: <your pubkey>
```

If you are in the set but never proposing, your node is not reachable — check
step 2's port test from outside.
