// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ActionInfo} from "@core/interfaces/ILOVE20Submit.sol";

/**
 * @title MockSubmit
 * @dev Mock Submit contract for unit testing
 */
contract MockSubmit {
    mapping(address => mapping(address => bool)) internal _canSubmit;
    mapping(address => mapping(uint256 => ActionInfo)) internal _actionInfos;

    function setCanSubmit(
        address tokenAddress,
        address account,
        bool value
    ) external {
        _canSubmit[tokenAddress][account] = value;
    }

    function canSubmit(
        address tokenAddress,
        address account
    ) external view returns (bool) {
        return _canSubmit[tokenAddress][account];
    }

    function setActionInfo(
        address tokenAddress,
        uint256 actionId,
        address whiteListAddress
    ) external {
        _actionInfos[tokenAddress][actionId]
            .body
            .whiteListAddress = whiteListAddress;
    }

    function setActionAuthor(
        address tokenAddress,
        uint256 actionId,
        address author
    ) external {
        _actionInfos[tokenAddress][actionId].head.author = author;
    }

    function actionInfo(
        address tokenAddress,
        uint256 actionId
    ) external view returns (ActionInfo memory) {
        return _actionInfos[tokenAddress][actionId];
    }
}
