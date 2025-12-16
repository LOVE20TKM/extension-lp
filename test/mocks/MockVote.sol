// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

/**
 * @title MockVote
 * @dev Mock Vote contract for unit testing
 */
contract MockVote {
    // tokenAddress => round => actionIds
    mapping(address => mapping(uint256 => uint256[])) private _votedActionIds;

    function setVotedActionIds(
        address tokenAddress,
        uint256 round,
        uint256 actionId
    ) external {
        _votedActionIds[tokenAddress][round].push(actionId);
    }

    function votedActionIdsCount(
        address tokenAddress,
        uint256 round
    ) external view returns (uint256) {
        return _votedActionIds[tokenAddress][round].length;
    }

    function votedActionIdsAtIndex(
        address tokenAddress,
        uint256 round,
        uint256 index
    ) external view returns (uint256) {
        return _votedActionIds[tokenAddress][round][index];
    }

    function isActionIdVoted(
        address tokenAddress,
        uint256 round,
        uint256 actionId
    ) external view returns (bool) {
        uint256[] storage actionIds = _votedActionIds[tokenAddress][round];
        for (uint256 i = 0; i < actionIds.length; i++) {
            if (actionIds[i] == actionId) {
                return true;
            }
        }
        return false;
    }
}
