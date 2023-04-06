// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {SignatureChecker} from "oz/utils/cryptography/SignatureChecker.sol";

/**
 * @title ERC4626Migrator
 * @author LHerskind
 * @notice Contract to be used for distributing tokens based on their shares of the total supply.
 * Practically LP tokens that can be migrated to ETH, DAI, and USDC.
 * Eth, Dai and USDC held by the contract will be used to distribute to users, so that the contract
 * is funded before users start using it, as they otherwise could simply sacrifice their share of the
 * assets.
 */
contract ERC4626Migrator is ReentrancyGuard {
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

    constructor(ERC20 _erc4626) {
        ERC4626Token = _erc4626;
    }

    // To receive eth
    receive() external payable {}

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
        // Validate the signature
        // Compute amounts to send to the user
        // Pull ERC4626 token from the user
        // Send assets to the user
        // Emit event

        // Checks that there either is a valid ECDSA signature provided, or that the calling contract
        // implements EIP-1271, and have approved the signature.
        if (!SignatureChecker.isValidSignatureNow(msg.sender, TOS, _signature)) {
            revert InvalidSignature(msg.sender, _signature);
        }

        // Compute the amount of ETH, DAI, and USDC to send to the user, based on the users share
        // of the asset.
        (uint256 ethToSend, uint256 daiToSend, uint256 usdcToSend) = _valuesToTransfer(_amount);

        ERC4626Token.safeTransferFrom(msg.sender, address(this), _amount);

        if (daiToSend > 0) DAI.safeTransfer(msg.sender, daiToSend);
        if (usdcToSend > 0) USDC.safeTransfer(msg.sender, usdcToSend);
        if (ethToSend > 0) {
            SafeTransferLib.safeTransferETH(msg.sender, ethToSend);
        }

        emit Migrated(msg.sender, _amount, ethToSend, daiToSend, usdcToSend);

        return (ethToSend, daiToSend, usdcToSend);
    }

    /**
     * @notice Computes the users shares of the ETH, DAI, and USDC balances
     * @dev Use a floating supply, as the ERC4626 token is not mintable or burnable
     * as Euler is non-operational.
     * @param _amount - the amount of ERC4626 token to be migrated
     * @return The amount of ETH that the user should receive
     * @return The amount of Dai that the user should receive
     * @return The amount of USDC that the user should receive
     */
    function _valuesToTransfer(uint256 _amount) internal view returns (uint256, uint256, uint256) {
        uint256 floatingSupply = ERC4626Token.totalSupply() - ERC4626Token.balanceOf(address(this));

        // Using the floating supply, compute the users share of each asset
        uint256 ethToSend = _amount.mulDivDown(address(this).balance, floatingSupply);
        uint256 daiToSend = _amount.mulDivDown(DAI.balanceOf(address(this)), floatingSupply);
        uint256 usdcToSend = _amount.mulDivDown(USDC.balanceOf(address(this)), floatingSupply);

        // @note Consider reverting if zeros to save users that preemptively try to migrate.

        return (ethToSend, daiToSend, usdcToSend);
    }
}
