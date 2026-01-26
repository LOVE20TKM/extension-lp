// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

/**
 * @title MockLaunch
 * @dev Mock Launch contract for unit testing
 */
contract MockLaunch {
    mapping(address => bool) private _isLOVE20Token;

    function isLOVE20Token(address tokenAddress) external view returns (bool) {
        return _isLOVE20Token[tokenAddress];
    }

    function setLOVE20Token(address tokenAddress, bool isLOVE20) external {
        _isLOVE20Token[tokenAddress] = isLOVE20;
    }
}
