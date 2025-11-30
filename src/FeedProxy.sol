// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "../lib/reactive-lib/src/abstract-base/AbstractCallback.sol";
import "../lib/chainlink-local/src/data-feeds/interfaces/AggregatorV3Interface.sol";

contract MirroredPriceFeedCallback is AbstractCallback, AggregatorV3Interface {
    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    address private sourceFeed;
    uint8 private feedDecimals;
    string private feedDescription;
    uint256 private constant VERSION = 1;

    mapping(uint80 => RoundData) private rounds;
    RoundData private latest;

    event FeedUpdated(
        uint80 indexed roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );

    constructor(
        address _callbackSender,
        address _sourceFeed,
        uint8 _decimals,
        string memory _description
    ) AbstractCallback(_callbackSender) payable {
        sourceFeed = _sourceFeed;
        feedDecimals = _decimals;
        feedDescription = _description;
    }

    function callback(
        address sender,                    // sender - ignored, provided for symmetry with other callbacks
        uint80 _roundId,
        int256 _answer,
        uint256 _startedAt,
        uint256 _updatedAt,
        uint80 _answeredInRound
    ) external authorizedSenderOnly rvmIdOnly(sender) {

        RoundData memory data = RoundData({
            roundId: _roundId,
            answer: _answer,
            startedAt: _startedAt,
            updatedAt: _updatedAt,
            answeredInRound: _answeredInRound
        });

        latest = data;
        rounds[_roundId] = data;

        emit FeedUpdated(
            _roundId,
            _answer,
            _startedAt,
            _updatedAt,
            _answeredInRound
        );
    }

    function decimals() external view override returns (uint8) {
        return feedDecimals;
    }

    function description() external view override returns (string memory) {
        return feedDescription;
    }

    function version() external pure override returns (uint256) {
        return VERSION;
    }

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        RoundData memory data = rounds[_roundId];
        return (
            data.roundId,
            data.answer,
            data.startedAt,
            data.updatedAt,
            data.answeredInRound
        );
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
        return (
            latest.roundId,
            latest.answer,
            latest.startedAt,
            latest.updatedAt,
            latest.answeredInRound
        );
    }
}

