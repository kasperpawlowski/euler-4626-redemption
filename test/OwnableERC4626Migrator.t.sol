// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {OwnableERC4626Migrator} from "../src/OwnableERC4626Migrator.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

contract OwnableERC4626MigratorTest is Test {
    using FixedPointMathLib for uint256;

    MockERC20 public ERC4626;
    OwnableERC4626Migrator public MIGRATOR;

    ERC20 public constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 public constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    function setUp() public {
        ERC4626 = new MockERC20("ERC4626", "ERC4626", 18);
        MIGRATOR = new OwnableERC4626Migrator(ERC20(address(ERC4626)));

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
        uint256 wethRate;
        uint256 daiRate;
        uint256 usdcRate;
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
        (vars.wethRate, vars.daiRate, vars.usdcRate) =
            _migratorAmounts(_totalSupply, _migrationAmount, _wethAmount, _daiAmount, _usdcAmount);

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
        uint256 expectedWeth = uint256(_migrationAmount).mulDivDown(vars.wethRate, 1e18);
        assertEq(weth, expectedWeth, "WETH");
        assertEq(weth, WETH.balanceOf(vars.user), "WETH");

        uint256 expectedDai = uint256(_migrationAmount).mulDivDown(vars.daiRate, 1e18);
        assertEq(dai, expectedDai, "DAI");
        assertEq(dai, DAI.balanceOf(vars.user), "DAI");

        uint256 expectedUsdc = uint256(_migrationAmount).mulDivDown(vars.usdcRate, 1e18);
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
        _migratorAmounts(_totalSupply, _migrationAmount, _wethAmount, _daiAmount, _usdcAmount);

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

    function testAdminRecoverOnBehalfOfUser(
        uint128 _totalSupply,
        uint128 _migrationAmount,
        uint128 _wethAmount,
        uint128 _daiAmount,
        uint128 _usdcAmount
    ) public {
        // Assume that a user for some reason cannot migrate his funds
        // He instead sends the funds to the Euler multisig and the "migrate" on his behalf
        vm.assume(_totalSupply > 0 && _totalSupply >= _migrationAmount);

        Intermediates memory vars;

        // Mints _totalSupply - _migrationAmount as floating
        (vars.wethRate, vars.daiRate, vars.usdcRate) =
            _migratorAmounts(_totalSupply, _migrationAmount, _wethAmount, _daiAmount, _usdcAmount);

        // Prepare user and mint funds to him
        vars.priv = 69;
        vars.user = vm.addr(vars.priv);
        ERC4626.mint(vars.user, _migrationAmount);

        assertEq(ERC4626.balanceOf(address(this)), 0, "ERC4626");
        assertEq(ERC4626.balanceOf(vars.user), _migrationAmount, "ERC4626");

        // User sends his funds to the Euler multisig
        // For now, we assume that euler multisig = address(this).
        vm.prank(vars.user);
        ERC4626.transfer(address(this), _migrationAmount);

        // Euler multisig migrates on behalf of the user
        (uint256 weth, uint256 dai, uint256 usdc) = MIGRATOR.adminMigrate(_migrationAmount, vars.user);

        assertEq(ERC4626.balanceOf(address(this)), _migrationAmount, "ERC4626");
        assertEq(ERC4626.balanceOf(vars.user), 0, "ERC4626");

        // Check the amounts returned
        uint256 expectedWeth = uint256(_migrationAmount).mulDivDown(vars.wethRate, 1e18);
        assertEq(weth, expectedWeth, "WETH");
        assertEq(weth, WETH.balanceOf(vars.user), "WETH");

        uint256 expectedDai = uint256(_migrationAmount).mulDivDown(vars.daiRate, 1e18);
        assertEq(dai, expectedDai, "DAI");
        assertEq(dai, DAI.balanceOf(vars.user), "DAI");

        uint256 expectedUsdc = uint256(_migrationAmount).mulDivDown(vars.usdcRate, 1e18);
        assertEq(usdc, expectedUsdc, "USDC");
        assertEq(usdc, USDC.balanceOf(vars.user), "USDC");
    }

    function testAdminRecoverEthAndUpdateRates(
        uint128 _totalSupply,
        uint128 _migrationAmount,
        uint128 _wethAmount,
        uint128 _daiAmount,
        uint128 _usdcAmount
    ) public {
        // Admin recover funds and then update rates to match new distribution.
        vm.assume(_totalSupply > 0 && _totalSupply >= _migrationAmount);
        vm.assume(_wethAmount > 100);

        Intermediates memory vars;

        (vars.wethRate, vars.daiRate, vars.usdcRate) =
            _migratorAmounts(_totalSupply, _migrationAmount, _wethAmount, _daiAmount, _usdcAmount);

        // Euler recover some of the WETH, and updates the rates
        MIGRATOR.adminRecover(address(WETH), _wethAmount / 2, address(this));

        uint256 expectedUpdatedWeth = uint256(_wethAmount - (_wethAmount / 2));

        uint256 a = uint256(_totalSupply) + uint256(_migrationAmount);
        expectedUpdatedWeth = expectedUpdatedWeth.mulDivDown(1e18, a);

        // Update the rates to payout less eth
        MIGRATOR.updateRates(a);

        assertEq(MIGRATOR.wethPerERC4626(), expectedUpdatedWeth, "New ETH not matching");
    }

    function testAdminRecoverDaiAndUpdateRates(
        uint128 _totalSupply,
        uint128 _migrationAmount,
        uint128 _wethAmount,
        uint128 _daiAmount,
        uint128 _usdcAmount
    ) public {
        // Admin recover funds and then update rates to match new distribution.
        vm.assume(_totalSupply > 0 && _totalSupply >= _migrationAmount);
        vm.assume(_daiAmount > 100);

        Intermediates memory vars;

        (vars.wethRate, vars.daiRate, vars.usdcRate) =
            _migratorAmounts(_totalSupply, _migrationAmount, _wethAmount, _daiAmount, _usdcAmount);

        // Euler recover some of the Dai, and updates the rates
        MIGRATOR.adminRecover(address(DAI), _daiAmount / 2, address(this));

        uint256 expectedUpdatedDai = uint256(_daiAmount - (_daiAmount / 2));

        uint256 a = uint256(_totalSupply) + uint256(_migrationAmount);
        expectedUpdatedDai = expectedUpdatedDai.mulDivDown(1e18, a);

        // Update the rates to payout less dai
        MIGRATOR.updateRates(a);

        assertEq(MIGRATOR.daiPerERC4626(), expectedUpdatedDai, "New DAI not matching");
    }

    function testUpdateRatesWith0Float() public {
        MIGRATOR.updateRates(0);
        assertEq(MIGRATOR.wethPerERC4626(), 0, "New WETH not matching");
        assertEq(MIGRATOR.daiPerERC4626(), 0, "New DAI not matching");
        assertEq(MIGRATOR.usdcPerERC4626(), 0, "New USDC not matching");
    }

    function testNonAdminAccessControl() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(1));
        MIGRATOR.updateRates(0);

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(1));
        MIGRATOR.adminRecover(address(0), 0, address(0));

        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(1));
        MIGRATOR.adminMigrate(0, address(0));
    }

    /**
     * UTILITY FUNCTIONS BELOW
     */

    function _migratorAmounts(
        uint256 _supply,
        uint256 _userAmount,
        uint256 _wethAmount,
        uint256 _daiAmount,
        uint256 _usdcAmount
    ) internal returns (uint256, uint256, uint256) {
        ERC4626.mint(address(0), _supply - _userAmount);

        // Mint assets to self, then transfer to the migrator
        deal(address(MIGRATOR.WETH()), address(this), _wethAmount);
        deal(address(MIGRATOR.DAI()), address(this), _daiAmount);
        deal(address(MIGRATOR.USDC()), address(this), _usdcAmount);

        WETH.transfer(address(MIGRATOR), _wethAmount);
        DAI.transfer(address(MIGRATOR), _daiAmount);
        USDC.transfer(address(MIGRATOR), _usdcAmount);

        uint256 supply = _supply + _userAmount;

        (uint256 a, uint256 b, uint256 c) = MIGRATOR.updateRates(supply);

        uint256 wethRate = _wethAmount.mulDivDown(1e18, supply);
        uint256 daiRate = _daiAmount.mulDivDown(1e18, supply);
        uint256 usdcRate = _usdcAmount.mulDivDown(1e18, supply);

        assertEq(a, wethRate);
        assertEq(b, daiRate);
        assertEq(c, usdcRate);

        return (wethRate, daiRate, usdcRate);
    }
}
