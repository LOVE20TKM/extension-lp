// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Test} from "forge-std/Test.sol";
import {ExtensionLp} from "../src/ExtensionLp.sol";
import {ExtensionLpFactoryV2} from "../src/ExtensionLpFactoryV2.sol";
import {ILpFactoryErrors} from "../src/interface/ILpFactory.sol";
import {ExtensionCenter} from "@extension/src/ExtensionCenter.sol";
import {ITokenJoinErrors} from "@extension/src/interface/ITokenJoin.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockUniswapV2Factory} from "./mocks/MockUniswapV2Factory.sol";
import {MockUniswapV2Pair} from "./mocks/MockUniswapV2Pair.sol";
import {MockStake} from "./mocks/MockStake.sol";
import {MockJoin} from "./mocks/MockJoin.sol";
import {MockVerify} from "./mocks/MockVerify.sol";
import {MockMint} from "./mocks/MockMint.sol";
import {MockSubmit} from "./mocks/MockSubmit.sol";
import {MockLaunch} from "./mocks/MockLaunch.sol";
import {MockVote} from "./mocks/MockVote.sol";
import {MockRandom} from "./mocks/MockRandom.sol";

contract ExtensionLpFactoryV2Test is Test {
    ExtensionLpFactoryV2 public factory;
    ExtensionCenter public center;
    MockERC20 public token;

    uint256 constant GOV_RATIO_MULTIPLIER = 2;
    uint256 constant MIN_GOV_RATIO = 1e17;

    function setUp() public {
        token = new MockERC20();
        MockUniswapV2Factory uniswapFactory = new MockUniswapV2Factory();
        MockStake stake = new MockStake();
        MockJoin join = new MockJoin();
        MockVerify verify = new MockVerify();
        MockMint mint = new MockMint();
        MockSubmit submit = new MockSubmit();
        MockLaunch launch = new MockLaunch();
        MockVote vote = new MockVote();
        MockRandom random = new MockRandom();

        center = new ExtensionCenter(
            address(uniswapFactory),
            address(launch),
            address(stake),
            address(submit),
            address(vote),
            address(join),
            address(verify),
            address(mint),
            address(random)
        );

        factory = new ExtensionLpFactoryV2(address(center));
        launch.setLOVE20Token(address(token), true);
    }

    function test_Initialize_RevertIfZeroJoinTokenAddress() public {
        vm.expectRevert(ITokenJoinErrors.InvalidJoinTokenAddress.selector);
        factory.createExtension(address(token), address(0), GOV_RATIO_MULTIPLIER, MIN_GOV_RATIO);
    }

    function test_Initialize_RevertIfInvalidJoinTokenAddress() public {
        MockERC20 invalidJoinToken = new MockERC20();

        vm.expectRevert(ILpFactoryErrors.InvalidJoinTokenFactory.selector);
        factory.createExtension(address(token), address(invalidJoinToken), GOV_RATIO_MULTIPLIER, MIN_GOV_RATIO);
    }

    function test_Initialize_AllowsFactoryPairThatDoesNotContainToken() public {
        MockERC20 tokenA = new MockERC20();
        MockERC20 tokenB = new MockERC20();
        MockUniswapV2Factory uniswapFactory = MockUniswapV2Factory(center.uniswapV2FactoryAddress());
        MockUniswapV2Pair unrelatedPair = MockUniswapV2Pair(uniswapFactory.createPair(address(tokenA), address(tokenB)));

        token.mint(address(this), 1e18);
        token.approve(address(factory), 1e18);

        address extensionAddress =
            factory.createExtension(address(token), address(unrelatedPair), GOV_RATIO_MULTIPLIER, MIN_GOV_RATIO);

        assertTrue(factory.exists(extensionAddress));
        assertEq(ExtensionLp(extensionAddress).JOIN_TOKEN_ADDRESS(), address(unrelatedPair));
    }
}
