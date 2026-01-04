// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test} from "forge-std/Test.sol";
import {
    TestExtensionLpHelper,
    FlowUserParams
} from "../TestExtensionLpHelper.sol";
import {ExtensionFactoryLp} from "../../src/ExtensionFactoryLp.sol";
import {ExtensionLp} from "../../src/ExtensionLp.sol";
import {IFactoryLp} from "../../src/interface/IFactoryLp.sol";
import {ILOVE20Token} from "@core/interfaces/ILOVE20Token.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    FIRST_PARENT_TOKEN_FUNDRAISING_GOAL
} from "@extension/lib/core/test/Constant.sol";

contract FactoryTest is Test {
    TestExtensionLpHelper public h;
    FlowUserParams public bob;
    FlowUserParams public alice;
    address public tokenAddress;

    function setUp() public {
        h = new TestExtensionLpHelper();
        (bob, alice) = h.finish_launch();
        tokenAddress = h.firstTokenAddress();
    }

    function test_factory_createExtension() public {
        ExtensionLp extension = h.createExtension(tokenAddress, 7, 2, 1e18);

        ExtensionFactoryLp factory = h.extensionFactory();
        assertTrue(
            factory.exists(address(extension)),
            "Extension should exist in factory"
        );
        assertEq(factory.extensionsCount(), 1, "Extensions count should be 1");
    }

    function test_factory_createMultipleExtensions() public {
        ExtensionLp extension1 = h.createExtension(tokenAddress, 7, 2, 1e18);

        ExtensionLp extension2 = h.createExtension(tokenAddress, 10, 3, 2e18);

        ExtensionFactoryLp factory = h.extensionFactory();
        assertTrue(
            factory.exists(address(extension1)),
            "Extension1 should exist"
        );
        assertTrue(
            factory.exists(address(extension2)),
            "Extension2 should exist"
        );
        assertEq(factory.extensionsCount(), 2, "Extensions count should be 2");
    }

    function test_factory_extensionParams() public {
        uint256 waitingBlocks = 7;
        uint256 govRatioMultiplier = 2;
        uint256 minGovVotes = 1e18;

        ExtensionLp extension = h.createExtension(
            tokenAddress,
            waitingBlocks,
            govRatioMultiplier,
            minGovVotes
        );

        assertEq(
            extension.TOKEN_ADDRESS(),
            tokenAddress,
            "tokenAddress should match"
        );
        assertEq(
            extension.WAITING_BLOCKS(),
            waitingBlocks,
            "WAITING_BLOCKS should match"
        );
        assertEq(
            extension.GOV_RATIO_MULTIPLIER(),
            govRatioMultiplier,
            "GOV_RATIO_MULTIPLIER should match"
        );
        assertEq(
            extension.MIN_GOV_VOTES(),
            minGovVotes,
            "MIN_GOV_VOTES should match"
        );
        assertEq(
            extension.JOIN_TOKEN_ADDRESS(),
            h.getPairAddress(tokenAddress),
            "joinTokenAddress should be pair address"
        );
    }

    function test_factory_extensions() public {
        ExtensionLp extension1 = h.createExtension(tokenAddress, 7, 2, 1e18);
        ExtensionLp extension2 = h.createExtension(tokenAddress, 10, 3, 2e18);

        ExtensionFactoryLp factory = h.extensionFactory();
        address[] memory extensions = factory.extensions();
        assertEq(extensions.length, 2, "Should have 2 extensions");
        assertEq(
            extensions[0],
            address(extension1),
            "First extension should match"
        );
        assertEq(
            extensions[1],
            address(extension2),
            "Second extension should match"
        );
    }

    function test_factory_extensionsAtIndex() public {
        ExtensionLp extension1 = h.createExtension(tokenAddress, 7, 2, 1e18);
        ExtensionLp extension2 = h.createExtension(tokenAddress, 10, 3, 2e18);

        ExtensionFactoryLp factory = h.extensionFactory();
        assertEq(
            factory.extensionsAtIndex(0),
            address(extension1),
            "Extension at index 0 should match"
        );
        assertEq(
            factory.extensionsAtIndex(1),
            address(extension2),
            "Extension at index 1 should match"
        );
    }

    function test_factory_revertIfInvalidJoinTokenAddress() public {
        ExtensionFactoryLp factory = h.extensionFactory();
        vm.expectRevert(IFactoryLp.InvalidJoinTokenAddress.selector);
        factory.createExtension(
            tokenAddress,
            address(0), // Invalid join token address
            7,
            2,
            1e18
        );
    }

    function test_factory_center() public view {
        ExtensionFactoryLp factory = h.extensionFactory();
        assertEq(
            factory.CENTER_ADDRESS(),
            address(h.extensionCenter()),
            "Center should match"
        );
    }

    function test_factory_differentTokens() public {
        // Create extension for parent token first
        ExtensionLp parentExtension = h.createExtensionWithDefaults(
            tokenAddress
        );
        address parentExtensionAddr = address(parentExtension);

        // Create child token
        h.stake_liquidity(bob);
        h.stake_token(bob);
        bob.actionId = h.submit_new_action_with_extension(
            bob,
            parentExtensionAddr
        );
        h.vote(bob);

        h.next_phase();
        // For ExtensionLp, users join through extension, not directly
        // So we skip the direct join and use extension join instead
        h.extension_join(bob, parentExtension, 1e18);
        h.next_phase();
        h.verify(bob);
        h.next_phase();
        h.mint_gov_reward(bob);
        h.mint_action_reward_for_extension(bob, parentExtensionAddr);

        // Launch child token
        h.stake_liquidity(bob);
        vm.startPrank(bob.userAddress);
        address childTokenAddress = h.launchContract().launchToken(
            "CHILD0",
            tokenAddress
        );
        vm.stopPrank();

        // Create extension for child token
        ExtensionLp childExtension = h.createExtensionWithDefaults(
            childTokenAddress
        );

        ExtensionFactoryLp factory = h.extensionFactory();
        assertTrue(
            factory.exists(address(childExtension)),
            "Child extension should exist"
        );
        assertEq(
            factory.extensionsCount(),
            2,
            "Should have 2 extensions (parent + child)"
        );
    }
}
