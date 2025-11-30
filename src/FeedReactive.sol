// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "../lib/reactive-lib/src/interfaces/IReactive.sol";
import "../lib/reactive-lib/src/abstract-base/AbstractReactive.sol";
import "../lib/reactive-lib/src/interfaces/ISystemContract.sol";

contract ChainlinkFeedMirrorReactive is IReactive, AbstractReactive {

    uint256 public originChainId;
    uint256 public destinationChainId;
    uint64 private constant GAS_LIMIT = 1_000_000;

    address private sourceFeed;
    address private callback;
    uint8 private feedDecimals;
    string private feedDescription;

    mapping(uint80 => uint256) private roundStartedAt;

    constructor(
        address _service,
        uint256 _originChainId,
        uint256 _destinationChainId,
        address _sourceFeed,
        uint256 _topic_0,
        address _callback,
        uint8 _decimals,
        string memory _description
    ) payable {

        service = ISystemContract(payable(_service));

        sourceFeed = _sourceFeed;
        feedDecimals = _decimals;
        feedDescription = _description;

        originChainId = _originChainId;
        destinationChainId = _destinationChainId;
        callback = _callback;

        if (!vm) {
            service.subscribe(
                originChainId,
                _sourceFeed,
                _topic_0,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }
    }

    function react(LogRecord calldata log) external vmOnly {

        int256 answer = int256(uint256(log.topic_1));
        uint80 roundId = uint80(uint256(log.topic_2));
        uint256 updatedAt = abi.decode(log.data, (uint256));


        uint256 startedAt = roundStartedAt[roundId];
        if (startedAt == 0) {
            startedAt = updatedAt;
        }

        uint80 answeredInRound = roundId;

        bytes memory payload = abi.encodeWithSignature(
            "callback(address,uint80,int256,uint256,uint256,uint80)",
            address(0),
            roundId,
            answer,
            startedAt,
            updatedAt,
            answeredInRound
        );

        emit Callback(
            destinationChainId,
            callback,
            GAS_LIMIT,
            payload
        );
    }
}
