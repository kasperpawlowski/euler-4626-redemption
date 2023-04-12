// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.18;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {Ownable} from "oz/access/Ownable.sol";
import {OwnableERC4626Migrator} from "./OwnableERC4626Migrator.sol";
import {OwnableERC4626MigratorWithOSQTH} from "./OwnableERC4626MigratorWithOSQTH.sol";

/**
 * @title MeanFinanceDistributor
 * @notice Contract to be used to distribute and set up the Mean Finance ERC4626 migration contracts.
 */
contract MeanFinanceDistributor is Ownable, ReentrancyGuard {
    using SafeTransferLib for ERC20;

    ERC20 constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 constant OSQTH = ERC20(0xf1B99e3E573A1a9C5E6B2Ce818b617F0E664E86B);

    address public constant eulerMultisig = 0xcAD001c30E96765aC90307669d578219D4fb1DCe;

    address public constant weweth4626 = 0xd4dE9D2Fc1607d1DF63E1c95ecBfa8d7946f5457;
    address public constant weusdc4626 = 0xCd0E5871c97C663D43c62B5049C123Bb45BfE2cC;
    address public constant webtc4626 = 0x48E345cb84895EAb4db4C44ff9B619cA0bE671d9;
    address public constant weosqth4626 = 0x20706baA0F89e2dccF48eA549ea5A13B9b30462f;
    address public constant wedai4626 = 0xc4113b7605D691E073c162809060b6C5Ae402F1e;
    address public constant welusd4626 = 0xb95E6eee428902C234855990E18a632fA34407dc;

    address public weweth4626Migrator;
    address public weusdc4626Migrator;
    address public webtc4626Migrator;
    address public weosqth4626Migrator;
    address public wedai4626Migrator;
    address public welusd4626Migrator;

    /** 
     * @notice Admin function to distribute and set up the Mean Finance ERC4626 migration contracts.
     * @dev Only owner can call this function
     */
    function distribute() external nonReentrant onlyOwner {
        // check balances
        require(WETH.balanceOf(address(this)) >= 26897136528044443767, "WETH balance incorrect");
        require(DAI.balanceOf(address(this)) >= 12405087959116478090418, "DAI balance incorrect");
        require(USDC.balanceOf(address(this)) >= 956175007, "USDC balance incorrect");
        require(OSQTH.balanceOf(address(this)) >= 37715590842656521648, "oSQTH balance incorrect");

        // deploy migrators
        weweth4626Migrator = address(new OwnableERC4626Migrator(ERC20(weweth4626)));
        weusdc4626Migrator = address(new OwnableERC4626Migrator(ERC20(weusdc4626)));
        webtc4626Migrator = address(new OwnableERC4626Migrator(ERC20(webtc4626)));
        weosqth4626Migrator = address(new OwnableERC4626MigratorWithOSQTH(ERC20(weosqth4626)));
        wedai4626Migrator = address(new OwnableERC4626Migrator(ERC20(wedai4626)));
        welusd4626Migrator = address(new OwnableERC4626Migrator(ERC20(welusd4626)));

        // transfer assets to migrators
        // WETH        
        WETH.safeTransfer(weweth4626Migrator, 13652442916353415992);
        WETH.safeTransfer(weusdc4626Migrator, 8911896590809932504);
        WETH.safeTransfer(webtc4626Migrator, 2367086147442822693);
        WETH.safeTransfer(weosqth4626Migrator, 330419796194197967);
        WETH.safeTransfer(wedai4626Migrator, 1386787823734313657);
        WETH.safeTransfer(welusd4626Migrator, 248503253509760954);

        // DAI
        DAI.safeTransfer(weweth4626Migrator, 6296571943916667766527);
        DAI.safeTransfer(weusdc4626Migrator, 4110209314522345174307);
        DAI.safeTransfer(webtc4626Migrator, 1091711447990678553913);
        DAI.safeTransfer(weosqth4626Migrator, 152391189707076801693);
        DAI.safeTransfer(wedai4626Migrator, 639593174393075053553);
        DAI.safeTransfer(welusd4626Migrator, 114610888586634740425);

        // USDC
        USDC.safeTransfer(weweth4626Migrator, 485335112);
        USDC.safeTransfer(weusdc4626Migrator, 316811896);
        USDC.safeTransfer(webtc4626Migrator, 84148311);
        USDC.safeTransfer(weosqth4626Migrator, 11746199);
        USDC.safeTransfer(wedai4626Migrator, 49299368);
        USDC.safeTransfer(welusd4626Migrator, 8834121);

        // OSQTH
        OSQTH.safeTransfer(weosqth4626Migrator, 37715590842656521648);

        // update rates (setup)
        OwnableERC4626Migrator(weweth4626Migrator).updateRates(ERC20(weweth4626).totalSupply());
        OwnableERC4626Migrator(weusdc4626Migrator).updateRates(ERC20(weusdc4626).totalSupply());
        OwnableERC4626Migrator(webtc4626Migrator).updateRates(ERC20(webtc4626).totalSupply());
        OwnableERC4626MigratorWithOSQTH(weosqth4626Migrator).updateRates(ERC20(weosqth4626).totalSupply());
        OwnableERC4626Migrator(wedai4626Migrator).updateRates(ERC20(wedai4626).totalSupply());
        OwnableERC4626Migrator(welusd4626Migrator).updateRates(ERC20(welusd4626).totalSupply());

        // transfer ownership to euler multisig
        OwnableERC4626Migrator(weweth4626Migrator).transferOwnership(eulerMultisig);
        OwnableERC4626Migrator(weusdc4626Migrator).transferOwnership(eulerMultisig);
        OwnableERC4626Migrator(webtc4626Migrator).transferOwnership(eulerMultisig);
        OwnableERC4626MigratorWithOSQTH(weosqth4626Migrator).transferOwnership(eulerMultisig);
        OwnableERC4626Migrator(wedai4626Migrator).transferOwnership(eulerMultisig);
        OwnableERC4626Migrator(welusd4626Migrator).transferOwnership(eulerMultisig);
    }

    /**
     * @notice Admin function to recover funds from the contract
     * @dev Only owner can call this function
     * @param _token - The token to recover
     * @param _amount - The amount of the token to recover
     * @param _to - The address to send the recovered funds to
     */
    function adminRecover(address _token, uint256 _amount, address _to) external onlyOwner {
        ERC20(_token).safeTransfer(_to, _amount);
    }
}
