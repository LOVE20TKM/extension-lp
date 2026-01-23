// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

/**
 * @title MockJoin
 * @notice Mock Join contract for testing
 */
contract MockJoin {
    uint256 internal _currentRound = 1;
    uint256 internal _originBlocks = 0;
    uint256 internal _phaseBlocks = 100;
    mapping(address => mapping(uint256 => mapping(address => uint256)))
        internal _amounts;

    function join(
        address tokenAddress,
        uint256 actionId,
        uint256 amount,
        string[] memory /* args */
    ) external {
        _amounts[tokenAddress][actionId][msg.sender] = amount;
    }

    function setCurrentRound(uint256 round) external {
        _currentRound = round;
    }

    function currentRound() external view returns (uint256) {
        return _currentRound;
    }

    function originBlocks() external view returns (uint256) {
        return _originBlocks;
    }

    function phaseBlocks() external view returns (uint256) {
        return _phaseBlocks;
    }

    function setOriginBlocks(uint256 originBlocks_) external {
        _originBlocks = originBlocks_;
    }

    function setPhaseBlocks(uint256 phaseBlocks_) external {
        _phaseBlocks = phaseBlocks_;
    }

    function amountByActionIdByAccount(
        address tokenAddress,
        uint256 actionId,
        address account
    ) external view returns (uint256) {
        return _amounts[tokenAddress][actionId][account];
    }
}
