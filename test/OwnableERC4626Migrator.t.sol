// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {OwnableERC4626Migrator} from "../src/OwnableERC4626Migrator.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {GnosisSafe as Safe} from "safe/GnosisSafe.sol";
import {Enum} from "safe/common/Enum.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

interface SignerLib {
    function getMessageHash(bytes memory) external view returns (bytes32);
}

contract OwnableERC4626MigratorTest is Test {
    using FixedPointMathLib for uint256;

    MockERC20 public ERC4626;
    OwnableERC4626Migrator public MIGRATOR;

    address public constant SIGNED_LIB_ADDR = address(0xA65387F16B013cf2Af4605Ad8aA5ec25a2cbA3a2);

    ERC20 public constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 public constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    // Testing with a gnosis safe, here Aztec Lister.
    Safe public constant MS = Safe(payable(0x68A36Aa8E309d5010ab4F9D6c5F1246b854D0b9e));
    address[2] public signers = [0xb143AE98179753CCB6F592a14F8357D2f8388bC6, 0x6fF2ea344696731003a1d4AAc4A0B2a4e24Bc7C5];

    receive() external payable {}

    function setUp() public {
        ERC4626 = new MockERC20("ERC4626", "ERC4626", 18);
        MIGRATOR = new OwnableERC4626Migrator(ERC20(address(ERC4626)));

        vm.label(address(DAI), "DAI");
        vm.label(address(USDC), "USDC");

        deal(address(DAI), address(MS), 0);
        deal(address(USDC), address(MS), 0);
        vm.deal(address(MS), 0);
    }

    struct Intermediates {
        uint256 priv;
        address user;
        bytes signature;
        uint256 eth;
        uint256 dai;
        uint256 usdc;
        uint256 userEthBalBefore;
        uint256 migratorEthBalBefore;
        uint256 ethRate;
        uint256 daiRate;
        uint256 usdcRate;
    }

    function testEOAHappyPath(
        uint128 _totalSupply,
        uint128 _migrationAmount,
        uint128 _ethAmount,
        uint128 _daiAmount,
        uint128 _usdcAmount
    ) public {
        vm.assume(_totalSupply > 0 && _totalSupply >= _migrationAmount);

        Intermediates memory vars;

        // Mints _totalSupply - _migrationAmount as floating
        (vars.ethRate, vars.daiRate, vars.usdcRate) =
            _migratorAmounts(_totalSupply, _migrationAmount, _ethAmount, _daiAmount, _usdcAmount);

        // Prepare user and mint funds to him
        vars.priv = 69;
        vars.user = vm.addr(vars.priv);
        ERC4626.mint(vars.user, _migrationAmount);

        // Approve the migrator to spend the user's ERC4626
        vm.prank(vars.user);
        ERC4626.approve(address(MIGRATOR), _migrationAmount);

        // Generate a signature
        bytes memory signature;
        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(vars.priv, MIGRATOR.TOS());
            signature = abi.encodePacked(r, s, v);
        }

        vars.userEthBalBefore = vars.user.balance;
        vars.migratorEthBalBefore = address(MIGRATOR).balance;

        assertEq(ERC4626.balanceOf(address(MIGRATOR)), 0, "ERC4626");
        assertEq(ERC4626.balanceOf(vars.user), _migrationAmount, "ERC4626");

        // Migrate
        vm.prank(vars.user);
        (uint256 eth, uint256 dai, uint256 usdc) = MIGRATOR.migrate(_migrationAmount, signature);

        assertEq(ERC4626.balanceOf(address(MIGRATOR)), _migrationAmount, "ERC4626");
        assertEq(ERC4626.balanceOf(vars.user), 0, "ERC4626");

        // Check the amounts returned
        uint256 expectedEth = uint256(_migrationAmount).mulDivDown(vars.ethRate, 1e18);
        assertEq(eth, expectedEth, "ETH expected return");
        // Assuming that we spent < 0.01 eth on fees.
        assertGe(vars.user.balance + 0.01e18, vars.userEthBalBefore + eth, "ETH user balance");
        assertEq(address(MIGRATOR).balance + eth, vars.migratorEthBalBefore, "ETH migrator balance");

        uint256 expectedDai = uint256(_migrationAmount).mulDivDown(vars.daiRate, 1e18);
        assertEq(dai, expectedDai, "DAI");
        assertEq(dai, DAI.balanceOf(vars.user), "DAI");

        uint256 expectedUsdc = uint256(_migrationAmount).mulDivDown(vars.usdcRate, 1e18);
        assertEq(usdc, expectedUsdc, "USDC");
        assertEq(usdc, USDC.balanceOf(vars.user), "USDC");
    }

    function testEOAInvalidTosSig(
        uint128 _totalSupply,
        uint128 _migrationAmount,
        uint128 _ethAmount,
        uint128 _daiAmount,
        uint128 _usdcAmount
    ) public {
        vm.assume(_totalSupply > 0 && _totalSupply >= _migrationAmount);

        Intermediates memory vars;

        // Mints _totalSupply - _migrationAmount as floating
        _migratorAmounts(_totalSupply, _migrationAmount, _ethAmount, _daiAmount, _usdcAmount);

        // Prepare user and mint funds to him
        vars.priv = 69;
        vars.user = vm.addr(vars.priv);
        ERC4626.mint(vars.user, _migrationAmount);

        // Approve the migrator to spend the user's ERC4626
        vm.prank(vars.user);
        ERC4626.approve(address(MIGRATOR), _migrationAmount);

        // Generate a signature
        bytes memory signature;
        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(vars.priv, bytes32("Some wrong message"));
            signature = abi.encodePacked(r, s, v);
        }

        // Migrate
        vm.expectRevert(abi.encodeWithSignature("InvalidSignature(address,bytes)", vars.user, signature));
        vm.prank(vars.user);
        MIGRATOR.migrate(_migrationAmount, signature);
    }

    function testGnosisSafeHappyPath(
        uint128 _totalSupply,
        uint128 _migrationAmount,
        uint128 _ethAmount,
        uint128 _daiAmount,
        uint128 _usdcAmount
    ) public {
        vm.assume(_totalSupply > 0 && _totalSupply >= _migrationAmount);

        Intermediates memory vars;

        // Mints _totalSupply - _migrationAmount as floating
        (vars.ethRate, vars.daiRate, vars.usdcRate) =
            _migratorAmounts(_totalSupply, _migrationAmount, _ethAmount, _daiAmount, _usdcAmount);

        ERC4626.mint(address(MS), _migrationAmount);

        // We prank the approval
        vm.prank(address(MS));
        ERC4626.approve(address(MIGRATOR), _migrationAmount);

        _signWithSafe(MIGRATOR.TOS());

        uint256 migratorEthBalBefore = address(MIGRATOR).balance;

        assertEq(ERC4626.balanceOf(address(MIGRATOR)), 0, "ERC4626");
        assertEq(ERC4626.balanceOf(address(MS)), _migrationAmount, "ERC4626");

        vm.prank(address(MS));
        (uint256 eth, uint256 dai, uint256 usdc) = MIGRATOR.migrate(_migrationAmount, "");

        assertEq(ERC4626.balanceOf(address(MIGRATOR)), _migrationAmount, "ERC4626");
        assertEq(ERC4626.balanceOf(address(MS)), 0, "ERC4626");

        uint256 expectedEth = uint256(_migrationAmount).mulDivDown(vars.ethRate, 1e18);
        assertEq(eth, expectedEth, "ETH");
        assertEq(eth, address(MS).balance, "ETH");
        assertEq(address(MIGRATOR).balance + eth, migratorEthBalBefore, "ETH");

        uint256 expectedDai = uint256(_migrationAmount).mulDivDown(vars.daiRate, 1e18);
        assertEq(dai, expectedDai, "DAI");
        assertEq(dai, DAI.balanceOf(address(MS)), "DAI");

        uint256 expectedUsdc = uint256(_migrationAmount).mulDivDown(vars.usdcRate, 1e18);
        assertEq(usdc, expectedUsdc, "USDC");
        assertEq(usdc, USDC.balanceOf(address(MS)), "USDC");
    }

    function testGnosisSafeInvalidSignature() public {
        uint256 migrationAmount = 10 ether;
        vm.expectRevert(abi.encodeWithSignature("InvalidSignature(address,bytes)", address(MS), bytes("")));
        vm.prank(address(MS));
        MIGRATOR.migrate(migrationAmount, "");
    }

    function testAdminRecoverOnBehalfOfUser(
        uint128 _totalSupply,
        uint128 _migrationAmount,
        uint128 _ethAmount,
        uint128 _daiAmount,
        uint128 _usdcAmount
    ) public {
        // Assume that a user for some reason cannot migrate his funds
        // He instead sends the funds to the Euler multisig and the "migrate" on his behalf
        vm.assume(_totalSupply > 0 && _totalSupply >= _migrationAmount);

        Intermediates memory vars;

        // Mints _totalSupply - _migrationAmount as floating
        (vars.ethRate, vars.daiRate, vars.usdcRate) =
            _migratorAmounts(_totalSupply, _migrationAmount, _ethAmount, _daiAmount, _usdcAmount);

        // Prepare user and mint funds to him
        vars.priv = 69;
        vars.user = vm.addr(vars.priv);
        ERC4626.mint(vars.user, _migrationAmount);

        // Generate a signature
        bytes memory signature;
        {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(vars.priv, MIGRATOR.TOS());
            signature = abi.encodePacked(r, s, v);
        }

        vars.userEthBalBefore = vars.user.balance;
        vars.migratorEthBalBefore = address(MIGRATOR).balance;

        assertEq(ERC4626.balanceOf(address(this)), 0, "ERC4626");
        assertEq(ERC4626.balanceOf(vars.user), _migrationAmount, "ERC4626");

        // User sends his funds to the Euler multisig
        // For now, we assume that euler multisig = address(this).
        vm.prank(vars.user);
        ERC4626.transfer(address(this), _migrationAmount);

        // Euler multisig migrates on behalf of the user
        (uint256 eth, uint256 dai, uint256 usdc) = MIGRATOR.adminMigrate(_migrationAmount, vars.user);

        assertEq(ERC4626.balanceOf(address(this)), _migrationAmount, "ERC4626");
        assertEq(ERC4626.balanceOf(vars.user), 0, "ERC4626");

        emit log_named_uint("rate", vars.ethRate);
        emit log_named_uint("rate", MIGRATOR.ethPerERC4626());

        // Check the amounts returned
        uint256 expectedEth = uint256(_migrationAmount).mulDivDown(vars.ethRate, 1e18);
        assertEq(eth, expectedEth, "ETH expected return");
        // Assuming that we spent < 0.01 eth on fees.
        assertGe(vars.user.balance + 0.01e18, vars.userEthBalBefore + eth, "ETH user balance");
        assertEq(address(MIGRATOR).balance + eth, vars.migratorEthBalBefore, "ETH migrator balance");

        uint256 expectedDai = uint256(_migrationAmount).mulDivDown(vars.daiRate, 1e18);
        assertEq(dai, expectedDai, "DAI");
        assertEq(dai, DAI.balanceOf(vars.user), "DAI");

        emit log_named_uint("rate", vars.usdcRate);
        emit log_named_uint("rate", MIGRATOR.usdcPerERC4626());

        uint256 expectedUsdc = uint256(_migrationAmount).mulDivDown(vars.usdcRate, 1e18);
        assertEq(usdc, expectedUsdc, "USDC");
        assertEq(usdc, USDC.balanceOf(vars.user), "USDC");
    }

    function testAdminRecoverEthAndUpdateRates(
        uint128 _totalSupply,
        uint128 _migrationAmount,
        uint96 _ethAmount,
        uint128 _daiAmount,
        uint128 _usdcAmount
    ) public {
        // Admin recover funds and then update rates to match new distribution.
        vm.assume(_totalSupply > 0 && _totalSupply >= _migrationAmount);
        vm.assume(_ethAmount > 100);

        Intermediates memory vars;

        (vars.ethRate, vars.daiRate, vars.usdcRate) =
            _migratorAmounts(_totalSupply, _migrationAmount, _ethAmount, _daiAmount, _usdcAmount);

        // Euler recover some of the Eth, and updates the rates
        MIGRATOR.adminRecover(address(0), _ethAmount / 2, address(this));

        uint256 expectedUpdatedEth = uint256(_ethAmount - (_ethAmount / 2));

        uint256 a = uint256(_totalSupply) + uint256(_migrationAmount);
        expectedUpdatedEth = expectedUpdatedEth.mulDivDown(1e18, a);

        // Update the rates to payout less eth
        MIGRATOR.updateRates(a);

        assertEq(MIGRATOR.ethPerERC4626(), expectedUpdatedEth, "New ETH not matching");
    }

    function testAdminRecoverDaiAndUpdateRates(
        uint128 _totalSupply,
        uint128 _migrationAmount,
        uint96 _ethAmount,
        uint128 _daiAmount,
        uint128 _usdcAmount
    ) public {
        // Admin recover funds and then update rates to match new distribution.
        vm.assume(_totalSupply > 0 && _totalSupply >= _migrationAmount);
        vm.assume(_daiAmount > 100);

        Intermediates memory vars;

        (vars.ethRate, vars.daiRate, vars.usdcRate) =
            _migratorAmounts(_totalSupply, _migrationAmount, _ethAmount, _daiAmount, _usdcAmount);

        // Euler recover some of the Eth, and updates the rates
        MIGRATOR.adminRecover(address(DAI), _daiAmount / 2, address(this));

        uint256 expectedUpdatedDai = uint256(_daiAmount - (_daiAmount / 2));

        uint256 a = uint256(_totalSupply) + uint256(_migrationAmount);
        expectedUpdatedDai = expectedUpdatedDai.mulDivDown(1e18, a);

        // Update the rates to payout less eth
        MIGRATOR.updateRates(a);

        assertEq(MIGRATOR.daiPerERC4626(), expectedUpdatedDai, "New ETH not matching");
    }

    function testUpdateRatesWith0Float() public {
        MIGRATOR.updateRates(0);
        assertEq(MIGRATOR.ethPerERC4626(), 0, "New ETH not matching");
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
        uint256 _ethAmount,
        uint256 _daiAmount,
        uint256 _usdcAmount
    ) internal returns (uint256, uint256, uint256) {
        ERC4626.mint(address(0), _supply - _userAmount);

        // Mint assets to self, then transfer to the migrator
        vm.deal(address(this), _ethAmount);
        deal(address(MIGRATOR.DAI()), address(this), _daiAmount);
        deal(address(MIGRATOR.USDC()), address(this), _usdcAmount);

        DAI.transfer(address(MIGRATOR), _daiAmount);
        USDC.transfer(address(MIGRATOR), _usdcAmount);
        (bool success,) = payable(address(MIGRATOR)).call{value: _ethAmount}("");
        require(success, "ETH transfer failed");

        uint256 supply = _supply + _userAmount;

        (uint256 a, uint256 b, uint256 c) = MIGRATOR.updateRates(supply);

        uint256 ethRate = _ethAmount.mulDivDown(1e18, supply);
        uint256 daiRate = _daiAmount.mulDivDown(1e18, supply);
        uint256 usdcRate = _usdcAmount.mulDivDown(1e18, supply);

        assertEq(a, ethRate);
        assertEq(b, daiRate);
        assertEq(c, usdcRate);

        return (ethRate, daiRate, usdcRate);
    }

    function _signWithSafe(bytes32 _hashToSign) internal {
        // Make sure that the signers have funds
        vm.deal(signers[0], 10 ether);
        vm.deal(signers[1], 10 ether);

        // Create the calldata for the call
        bytes memory data = abi.encodeWithSignature("signMessage(bytes)", abi.encode(_hashToSign));

        // Generate the action hash using a delegatecall to the signed library by gnosis
        bytes32 actionHash = MS.getTransactionHash(
            address(SIGNED_LIB_ADDR),
            0,
            data,
            Enum.Operation.DelegateCall,
            1e6,
            1e6,
            0,
            address(0),
            address(0),
            MS.nonce()
        );

        vm.prank(signers[0]);
        MS.approveHash(actionHash);

        vm.startPrank(signers[1]);
        MS.approveHash(actionHash);

        // Generates the signature that is to be passed to the safe for execution.
        // Note that addresses need to be sorted in ascending order and that
        // v == 1 is used to indicate towards the safe that the signature is already
        // an approved hash. We use the approved hash to allow us to use prank for
        // addresses where we don't have the private key.
        bytes memory sigs = abi.encodePacked(
            bytes32(uint256(uint160(signers[1]))),
            bytes32(uint256(0)),
            uint8(1),
            bytes32(uint256(uint160(signers[0]))),
            bytes32(uint256(0)),
            uint8(1)
        );

        // Execute the transaction to update storage variable that approve signature.
        MS.execTransaction(
            address(SIGNED_LIB_ADDR), 0, data, Enum.Operation.DelegateCall, 1e6, 1e6, 0, address(0), payable(0), sigs
        );
        vm.stopPrank();
    }
}
