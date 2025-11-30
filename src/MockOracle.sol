// SPDX-License-Identifier: GPL-2.0-or-later

// MOCK ORACLE FOR TESTING

pragma solidity >=0.8.0;

contract MockOracle {
    event AnswerUpdated(
        int256 indexed current,
        uint256 indexed roundId,
        uint256 updatedAt
    );

    int256 _current = 100;
    uint256 _roundId = 1;

    function emitEvent() external {
        emit AnswerUpdated(
            _current,
            _roundId,
            block.timestamp
        );
        _current += 1;
        _roundId += 1;
    }
}

