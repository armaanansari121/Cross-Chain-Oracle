## Reactive Chainlink Feed Mirror

Mirror a Chainlink price feed from an origin chain to a destination chain using **Reactive Smart Contracts**. The Reactive Network listens for feed updates on the origin chain, then delivers a callback that is exposed as a standard `AggregatorV3Interface` on the destination chain, so any consumer can read the mirrored feed without changing its integration code.

### Components
- `src/FeedReactive.sol` (`ChainlinkFeedMirrorReactive`): reactive contract deployed to the Reactive VM. Subscribes to `AnswerUpdated` logs on the origin feed and emits a `Callback` for each update.
- `src/FeedProxy.sol` (`MirroredPriceFeedCallback`): destination-side callback that implements `AggregatorV3Interface`, stores the mirrored rounds, and emits `FeedUpdated` on every update.
- `src/MockOracle.sol`: simple test oracle that emits `AnswerUpdated` events so you can dry-run the pipeline on a dev network.

### Data Flow (design choices)
1. On deployment, `ChainlinkFeedMirrorReactive` calls `service.subscribe(originChainId, sourceFeed, topic_0, ...)` so the Reactive Network relays only the Chainlink `AnswerUpdated(int256,uint256,uint256)` events you care about.
2. The reactive contract pulls the price from `topic_1`, round ID from `topic_2`, and `updatedAt` from log data. It reuses `roundId` as `answeredInRound` and tracks `startedAt` per round (defaulting to `updatedAt` if missing).
3. The destination callback implements the exact Chainlink `AggregatorV3Interface` (`decimals`, `description`, `version`, `getRoundData`, `latestRoundData`) so downstream consumers can point to the mirrored feed without code changes.
5. **Safety controls** – Only the Reactive system contract can invoke `callback`, enforced by `authorizedSenderOnly` and RVM instance checks in `AbstractCallback` / `AbstractReactive`.

### Repository Layout
- `src/FeedReactive.sol` – reactive listener and callback emitter
- `src/FeedProxy.sol` – on-destination feed storage & Chainlink interface
- `src/MockOracle.sol` – local testing helper
- `lib/reactive-lib` – Reactive Network abstractions (system contract, auth helpers)
- `lib/chainlink-local` – Chainlink aggregator interfaces

### Prerequisites
- Foundry toolchain (`forge`, `cast`, `anvil`)
- Access to an origin RPC (e.g., Sepolia), a destination RPC, and a Reactive VM RPC
- Private keys with funds on each network for deployments and callback gas

### Configuration
Copy `.env.example` to `.env` and fill in the values that match your setup:

- `ORIGIN_RPC` / `ORIGIN_CHAIN_ID` / `ORIGIN_PRIVATE_KEY` – network where the Chainlink feed lives
- `DESTINATION_RPC` / `DESTINATION_CHAIN_ID` / `DESTINATION_PRIVATE_KEY` – network where the mirrored feed will be consumed
- `REACTIVE_RPC` / `REACTIVE_PRIVATE_KEY` – Reactive VM endpoint and deployer key
- `SYSTEM_CONTRACT_ADDR` – Reactive system contract address (typically `0x...fffFfF`)
- `DESTINATION_CALLBACK_PROXY_ADDR` – address allowed to trigger `callback` (Reactive system dispatcher on destination)
- `TOPIC_0` – keccak hash of `AnswerUpdated(int256,uint256,uint256)`
- `ORIGIN_ADDR` – address of the source Chainlink feed on the origin chain
- `CALLBACK_ADDR` – address of the deployed callback contract on the destination chain (used when wiring the reactive contract)
- `REACTIVE_ADDR` – optional address of the reactive contract once deployed (for reference)

### Build
```bash
forge build
```

### Deployment Steps
1) **Deploy the destination callback (Chainlink-compatible proxy)**
```bash
forge create src/FeedProxy.sol:MirroredPriceFeedCallback \
  --broadcast \
  --rpc-url $DESTINATION_RPC \
  --private-key $DESTINATION_PRIVATE_KEY \
  --value 0.5ether \
  --constructor-args $DESTINATION_CALLBACK_PROXY_ADDR $ORIGIN_ADDR <decimals> "<description>"
```
- Use the origin feed’s `decimals()` and `description()` values so consumers see identical metadata.
- Set the `$CALLBACK_ADDRESS` variable to the new address.

2) **Deploy the reactive listener to the Reactive VM**
```bash
forge create src/FeedReactive.sol:ChainlinkFeedMirrorReactive \
  --broadcast \
  --rpc-url $REACTIVE_RPC \
  --private-key $REACTIVE_PRIVATE_KEY \
  --value 0.5ether \
  --constructor-args $SYSTEM_CONTRACT_ADDR $ORIGIN_CHAIN_ID $DESTINATION_CHAIN_ID $ORIGIN_ADDR $TOPIC_0 <callback_address> <decimals> "<description>"
```
- On deployment, the contract auto-subscribes to the origin feed events (when running against the Reactive Network, not inside the VM copy).

3) **(Optional) Local dry-run with the mock oracle**
- Deploy `MockOracle` to your origin dev chain and call `emitEvent()` to produce `AnswerUpdated` logs. The Reactive Network should relay them, invoking `callback` on the destination and updating `latestRoundData`.
- Or you can directly use a real Chainlink Price Feed to skip the hassle.

### How to Read the Mirrored Feed
- Latest values: `cast call $CALLBACK_ADDR "latestRoundData()(uint80,int256,uint256,uint256,uint80)" --rpc-url $DESTINATION_RPC`
- Historical round: `cast call $CALLBACK_ADDRESS "getRoundData(uint80)(uint80,int256,uint256,uint256,uint80)" <roundId> --rpc-url $DESTINATION_RPC`
- Metadata: `cast call $CALLBACK_ADDR "decimals()(uint8)" --rpc-url $DESTINATION_RPC` and same for `description()`.

### Testing & Maintenance
- Static checks: `forge fmt` and `forge build`

### Notes
- Only the Reactive system contract is authorized to call `callback`; user transactions cannot mutate the mirrored state.

### Transactions Trace: 
- FeedProxy.sol:MirroredPriceFeedCallback Deployment Transaction: https://lasna.reactscan.net/address/0xe7581d539156e9811c7c36bfbcd68741fa1fdfbc/137
- FeedReactive.sol:ChainlinkFeedMirrorReactive Deployment Transaction: https://lasna.reactscan.net/address/0xe7581d539156e9811c7c36bfbcd68741fa1fdfbc/138
- Origin "ETH / USD" Feed Answer Updated Transaction: https://sepolia.etherscan.io/tx/0xc6f7f32a23f0fa2740d9422b2c18a2da95c3b83f86a7dcac71a386a86a168cb6#eventlog
- ChainlinkFeedMirrorReactive - React To Event Transaction: https://lasna.reactscan.net/address/0xe7581d539156e9811c7c36bfbcd68741fa1fdfbc/139
- MirroredPriceFeedCallback - Callback Transaction: https://lasna.reactscan.net/tx/0xbbc4faf7ebd1dd5d684d58ecc775eac0afea97fe65cd3f0e7ad4111cb026ef8f

For future event emissions and reactions observe the following Smart Contracts:
- FeedProxy.sol:MirroredPriceFeedCallback ==> https://lasna.reactscan.net/address/0xe7581d539156e9811c7c36bfbcd68741fa1fdfbc/contract/0x5a756ce84899169264e845d1703ffc27d71370b0?screen=transactions
- FeedReactive.sol:ChainlinkFeedMirrorReactive ==> https://lasna.reactscan.net/address/0xe7581d539156e9811c7c36bfbcd68741fa1fdfbc/contract/0x7fb85cb094c60ba31c66aab0ca07149eef857461?screen=transactions
- Origin "ETH / USD" Feed ==> https://sepolia.etherscan.io/address/0x719E22E3D4b690E5d96cCb40619180B5427F14AE#events
