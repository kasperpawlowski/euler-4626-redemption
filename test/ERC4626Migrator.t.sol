// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ERC4626Migrator} from "../src/ERC4626Migrator.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract ERC4626MigratorTest is Test {
    using FixedPointMathLib for uint256;

    MockERC20 public ERC4626;
    ERC4626Migrator public MIGRATOR;

    ERC20 public constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 public constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    function setUp() public {
        ERC4626 = new MockERC20("ERC4626", "ERC4626", 18);
        MIGRATOR = new ERC4626Migrator(ERC20(address(ERC4626)));

        vm.label(address(WETH), "WETH");
        vm.label(address(DAI), "DAI");
        vm.label(address(USDC), "USDC");
    }

    struct Intermediates {
        uint256 priv;
        address user;
        uint256 weth;
        uint256 dai;
        uint256 usdc;
    }

    function testHappyPath(
        uint128 _totalSupply,
        uint128 _migrationAmount,
        uint128 _wethAmount,
        uint128 _daiAmount,
        uint128 _usdcAmount
    ) public {
        vm.assume(_totalSupply > 0 && _totalSupply >= _migrationAmount);

        Intermediates memory vars;

        // Mints _totalSupply - _migrationAmount as floating
        _migratorAmounts(_totalSupply - _migrationAmount, _wethAmount, _daiAmount, _usdcAmount);

        // Prepare user and mint funds to him
        vars.priv = 69;
        vars.user = vm.addr(vars.priv);
        ERC4626.mint(vars.user, _migrationAmount);

        // Approve the migrator to spend the user's ERC4626
        vm.prank(vars.user);
        ERC4626.approve(address(MIGRATOR), _migrationAmount);

        // Generate an acceptance token
        bytes32 acceptanceToken = keccak256(abi.encodePacked(vars.user, MIGRATOR.termsAndConditionsHash()));

        assertEq(ERC4626.balanceOf(address(MIGRATOR)), 0, "ERC4626");
        assertEq(ERC4626.balanceOf(vars.user), _migrationAmount, "ERC4626");

        // Migrate
        vm.prank(vars.user);
        (uint256 weth, uint256 dai, uint256 usdc) = MIGRATOR.migrate(_migrationAmount, acceptanceToken);

        assertEq(ERC4626.balanceOf(address(MIGRATOR)), _migrationAmount, "ERC4626");
        assertEq(ERC4626.balanceOf(vars.user), 0, "ERC4626");

        // Check the amounts returned
        uint256 expectedWeth = uint256(_migrationAmount).mulDivDown(_wethAmount, _totalSupply);
        assertEq(weth, expectedWeth, "WETH");
        assertEq(weth, WETH.balanceOf(vars.user), "WETH");

        uint256 expectedDai = uint256(_migrationAmount).mulDivDown(_daiAmount, _totalSupply);
        assertEq(dai, expectedDai, "DAI");
        assertEq(dai, DAI.balanceOf(vars.user), "DAI");

        uint256 expectedUsdc = uint256(_migrationAmount).mulDivDown(_usdcAmount, _totalSupply);
        assertEq(usdc, expectedUsdc, "USDC");
        assertEq(usdc, USDC.balanceOf(vars.user), "USDC");
    }

    function testInvalidAcceptanceToken(
        uint128 _totalSupply,
        uint128 _migrationAmount,
        uint128 _wethAmount,
        uint128 _daiAmount,
        uint128 _usdcAmount
    ) public {
        vm.assume(_totalSupply > 0 && _totalSupply >= _migrationAmount);

        Intermediates memory vars;

        // Mints _totalSupply - _migrationAmount as floating
        _migratorAmounts(_totalSupply - _migrationAmount, _wethAmount, _daiAmount, _usdcAmount);

        // Prepare user and mint funds to him
        vars.priv = 69;
        vars.user = vm.addr(vars.priv);
        ERC4626.mint(vars.user, _migrationAmount);

        // Approve the migrator to spend the user's ERC4626
        vm.prank(vars.user);
        ERC4626.approve(address(MIGRATOR), _migrationAmount);

        // Generate an acceptance token
        bytes32 acceptanceToken = keccak256(abi.encodePacked(vars.user, bytes32(uint(MIGRATOR.termsAndConditionsHash()) + 1)));

        // Migrate
        vm.expectRevert(abi.encodeWithSignature("InvalidAcceptanceToken(address,bytes32)", vars.user, acceptanceToken));
        vm.prank(vars.user);
        MIGRATOR.migrate(_migrationAmount, acceptanceToken);
    }

    /**
     * UTILITY FUNCTIONS BELOW
     */

    function _migratorAmounts(uint256 _supply, uint256 _wethAmount, uint256 _daiAmount, uint256 _usdcAmount) internal {
        ERC4626.mint(address(0), _supply);

        // Mint assets to self, then transfer to the migrator
        deal(address(MIGRATOR.WETH()), address(this), _wethAmount);
        deal(address(MIGRATOR.DAI()), address(this), _daiAmount);
        deal(address(MIGRATOR.USDC()), address(this), _usdcAmount);

        WETH.transfer(address(MIGRATOR), _wethAmount);
        DAI.transfer(address(MIGRATOR), _daiAmount);
        USDC.transfer(address(MIGRATOR), _usdcAmount);
    }
}
