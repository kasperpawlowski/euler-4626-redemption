// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {SignatureChecker} from "oz/utils/cryptography/SignatureChecker.sol";
import {Ownable2Step} from "oz/access/Ownable2Step.sol";

/**
 * @title ERC4626Migrator
 * @author LHerskind
 * @notice Contract to be used for distributing tokens based on their shares of the total supply.
 * Practically LP tokens that can be migrated to ETH, DAI, and USDC.
 * Eth, Dai and USDC held by the contract will be used to distribute to users, so that the contract
 * is funded before users start using it, as they otherwise could simply sacrifice their share of the
 * assets.
 * With admin functions, allowing an administrator to recover funds from the contract, update rates or
 * emulate migrations by users, if they for some reason are unable to migrate.
 */
contract OwnableERC4626Migrator is Ownable2Step, ReentrancyGuard {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    error InvalidSignature(address user, bytes signature);

    event Migrated(address indexed user, uint256 amount, uint256 ethAmount, uint256 daiAmount, uint256 usdcAmount);

    // @todo Replace this with the real hash
    bytes32 public constant TOS = bytes32("TOS");

    ERC20 public constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 public constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    // Only really safe it not possible to mint or burn tokens with an admin.
    // If admin can burn and mint. Admin could simply mint tokens and exit or burn from the contract to inflate.
    ERC20 public immutable ERC4626Token;

    // @todo Don't need to be a full 256 bits each
    uint256 public ethPerERC4626;
    uint256 public daiPerERC4626;
    uint256 public usdcPerERC4626;

    constructor(ERC20 _erc4626) {
        ERC4626Token = _erc4626;
    }

    // To receive eth
    receive() external payable {}

    /**
     * @notice Updates the asset per ERC4626 token rate based on the floating supply
     * Floating supply provided to allow owner to account for asset held by this contract + euler
     * multisig or other contracts.
     * @param _floatingSupply - The supply of ERC4626 tokens that are "redeemable" for assets
     */
    function updateRates(uint256 _floatingSupply) external onlyOwner returns (uint256, uint256, uint256) {
        if (_floatingSupply == 0) {
            return (0, 0, 0);
        }

        ethPerERC4626 = address(this).balance.mulDivDown(1e18, _floatingSupply);
        daiPerERC4626 = DAI.balanceOf(address(this)).mulDivDown(1e18, _floatingSupply);
        usdcPerERC4626 = USDC.balanceOf(address(this)).mulDivDown(1e18, _floatingSupply);
        return (ethPerERC4626, daiPerERC4626, usdcPerERC4626);
    }

    /**
     * @notice Admin function to recover funds from the contract
     * @dev Only owner can call this function
     * @param _token - The token to recover
     * @param _amount - The amount of the token to recover
     * @param _to - The address to send the recovered funds to
     */
    function adminRecover(address _token, uint256 _amount, address _to) external onlyOwner {
        if (_token == address(0)) {
            SafeTransferLib.safeTransferETH(_to, _amount);
        } else {
            ERC20(_token).safeTransfer(_to, _amount);
        }
    }

    /**
     * @notice Admin function simulate migration of ERC4626 token to ETH, DAI, and USDC without
     * actually sacrificing ERC4626.
     * @param _amount - The amount of ERC4626 token to be migrated
     * @param _to - The address to send the recovered funds to
     * @return The amount of eth sent to the user
     * @return The amount of dai sent to the user
     * @return The amount of usdc sent to the user
     */
    function adminMigrate(uint256 _amount, address _to) external onlyOwner returns (uint256, uint256, uint256) {
        return _exitFunds(_amount, _to, false);
    }

    /**
     * @notice Migrates ERC4626 token to ETH, DAI, and USDC
     * @dev Reentry guard.
     * @param _amount - The amount of ERC4626 token to be migrated
     * @dev Signature is formatted as [r, s, v]
     * @dev Supports EIP-1271 signatures.
     * @param _signature - A valid signature by the user signing over the TOS
     * @return The amount of eth sent to the user
     * @return The amount of dai sent to the user
     * @return The amount of usdc sent to the user
     */
    function migrate(uint256 _amount, bytes calldata _signature)
        external
        nonReentrant
        returns (uint256, uint256, uint256)
    {
        // Checks that there either is a valid ECDSA signature provided, or that the calling contract
        // implements EIP-1271, and have approved the signature.
        if (!SignatureChecker.isValidSignatureNow(msg.sender, TOS, _signature)) {
            revert InvalidSignature(msg.sender, _signature);
        }

        return _exitFunds(_amount, msg.sender, true);
    }

    /**
     * @notice Internal function to compute the amount of ETH, DAI, and USDC to send to the user.
     * @param _amount - The amount of ERC4626 token to be migrated
     * @param _to - The address to send the recovered funds to
     * @param _pullFunds - Whether to pull ERC4626 token from the user
     * @return The amount of eth sent to the user
     * @return The amount of dai sent to the user
     * @return The amount of usdc sent to the user
     */
    function _exitFunds(uint256 _amount, address _to, bool _pullFunds) internal returns (uint256, uint256, uint256) {
        uint256 ethToSend = _amount.mulDivDown(ethPerERC4626, 1e18);
        uint256 daiToSend = _amount.mulDivDown(daiPerERC4626, 1e18);
        uint256 usdcToSend = _amount.mulDivDown(usdcPerERC4626, 1e18);

        if (_pullFunds) {
            ERC4626Token.safeTransferFrom(msg.sender, address(this), _amount);
        }

        if (daiToSend > 0) DAI.safeTransfer(_to, daiToSend);
        if (usdcToSend > 0) USDC.safeTransfer(_to, usdcToSend);
        if (ethToSend > 0) {
            SafeTransferLib.safeTransferETH(_to, ethToSend);
        }

        emit Migrated(_to, _amount, ethToSend, daiToSend, usdcToSend);

        return (ethToSend, daiToSend, usdcToSend);
    }
}
