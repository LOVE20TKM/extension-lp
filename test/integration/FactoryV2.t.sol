// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test} from "forge-std/Test.sol";
import {TestExtensionLpHelper, FlowUserParams} from "../TestExtensionLpHelper.sol";
import {ExtensionLpFactoryV2} from "../../src/ExtensionLpFactoryV2.sol";
import {ExtensionLp} from "../../src/ExtensionLp.sol";
import {ITokenJoinErrors} from "@extension/src/interface/ITokenJoin.sol";
import {IUniswapV2Factory} from "@core/uniswap-v2-core/interfaces/IUniswapV2Factory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestERC20} from "@extension/lib/core/test/TestERC20.sol";

contract FactoryV2Test is Test {
    TestExtensionLpHelper public h;
    FlowUserParams public bob;
    FlowUserParams public alice;
    address public tokenAddress;
    ExtensionLpFactoryV2 public factory;

    function setUp() public {
        h = new TestExtensionLpHelper();
        (bob, alice) = h.finish_launch();
        tokenAddress = h.firstTokenAddress();
        factory = new ExtensionLpFactoryV2(address(h.extensionCenter()));
    }

    function test_factory_v2_revertIfInvalidJoinTokenAddress() public {
        vm.expectRevert(ITokenJoinErrors.InvalidJoinTokenAddress.selector);
        factory.createExtension(tokenAddress, address(0), 2, 1e18);
    }

    function test_factory_v2_acceptsKnownFactoryLpEvenIfItDoesNotContainToken() public {
        TestERC20 tokenA = new TestERC20("TOKEN_A", "TKA");
        TestERC20 tokenB = new TestERC20("TOKEN_B", "TKB");
        address unrelatedPair = IUniswapV2Factory(h.uniswapV2Factory()).createPair(address(tokenA), address(tokenB));

        h.forceMint(tokenAddress, address(this), 1e18);
        IERC20(tokenAddress).approve(address(factory), 1e18);

        address extensionAddress = factory.createExtension(tokenAddress, unrelatedPair, 2, 1e17);

        assertTrue(factory.exists(extensionAddress), "Extension should exist");
        assertEq(
            ExtensionLp(extensionAddress).JOIN_TOKEN_ADDRESS(),
            unrelatedPair,
            "joinTokenAddress should match unrelated factory pair"
        );
    }
}
