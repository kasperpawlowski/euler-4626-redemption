// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import {MeanFinanceDistributor} from "../src/MeanFinanceDistributor.sol";
import {OwnableERC4626Migrator} from "../src/OwnableERC4626Migrator.sol";
import {OwnableERC4626MigratorWithOSQTH} from "../src/OwnableERC4626MigratorWithOSQTH.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract MeanFinanceDistributorTest is Test {
    MeanFinanceDistributor public DISTRIBUTOR;

    ERC20 constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 constant OSQTH = ERC20(0xf1B99e3E573A1a9C5E6B2Ce818b617F0E664E86B);

    address constant eulerMultisig = 0xcAD001c30E96765aC90307669d578219D4fb1DCe;

    function setUp() public {
        DISTRIBUTOR = new MeanFinanceDistributor();

        vm.label(address(WETH), "WETH");
        vm.label(address(DAI), "DAI");
        vm.label(address(USDC), "USDC");
        vm.label(address(OSQTH), "OSQTH");
    }

    function testDistribute() public {
        // Mint assets to self, then transfer to the distributor
        deal(address(WETH), address(this), 26897136528044443767);
        deal(address(DAI), address(this), 12405087959116478090418);
        deal(address(USDC), address(this), 956175007);
        deal(address(OSQTH), address(this), 37715590842656521648);

        WETH.transfer(address(DISTRIBUTOR), WETH.balanceOf(address(this)));
        DAI.transfer(address(DISTRIBUTOR), DAI.balanceOf(address(this)));
        USDC.transfer(address(DISTRIBUTOR), USDC.balanceOf(address(this)));
        OSQTH.transfer(address(DISTRIBUTOR), OSQTH.balanceOf(address(this)));

        // check constants
        assertEq(DISTRIBUTOR.eulerMultisig(), 0xcAD001c30E96765aC90307669d578219D4fb1DCe, "Euler Multisig");
        assertEq(DISTRIBUTOR.weweth4626(), 0xd4dE9D2Fc1607d1DF63E1c95ecBfa8d7946f5457, "weweth4626");
        assertEq(DISTRIBUTOR.weusdc4626(), 0xCd0E5871c97C663D43c62B5049C123Bb45BfE2cC, "weusdc4626");
        assertEq(DISTRIBUTOR.webtc4626(), 0x48E345cb84895EAb4db4C44ff9B619cA0bE671d9, "webtc4626");
        assertEq(DISTRIBUTOR.weosqth4626(), 0x20706baA0F89e2dccF48eA549ea5A13B9b30462f, "weosqth4626");
        assertEq(DISTRIBUTOR.wedai4626(), 0xc4113b7605D691E073c162809060b6C5Ae402F1e, "wedai4626");
        assertEq(DISTRIBUTOR.welusd4626(), 0xb95E6eee428902C234855990E18a632fA34407dc, "welusd4626");

        // Distribute
        DISTRIBUTOR.distribute();

        // Check results

        address weweth4626Migrator = DISTRIBUTOR.weweth4626Migrator();
        address weusdc4626Migrator = DISTRIBUTOR.weusdc4626Migrator();
        address webtc4626Migrator = DISTRIBUTOR.webtc4626Migrator();
        address weosqth4626Migrator = DISTRIBUTOR.weosqth4626Migrator();
        address wedai4626Migrator = DISTRIBUTOR.wedai4626Migrator();
        address welusd4626Migrator = DISTRIBUTOR.welusd4626Migrator();

        assertEq(WETH.balanceOf(weweth4626Migrator), 13652442916353415992, "WETH_weweth4626Migrator");
        assertEq(WETH.balanceOf(weusdc4626Migrator), 8911896590809932504, "WETH_weusdc4626Migrator");
        assertEq(WETH.balanceOf(webtc4626Migrator), 2367086147442822693, "WETH_webtc4626Migrator");
        assertEq(WETH.balanceOf(weosqth4626Migrator), 330419796194197967, "WETH_weosqth4626Migrator");
        assertEq(WETH.balanceOf(wedai4626Migrator), 1386787823734313657, "WETH_wedai4626Migrator");
        assertEq(WETH.balanceOf(welusd4626Migrator), 248503253509760954, "WETH_welusd4626Migrator");

        assertEq(DAI.balanceOf(weweth4626Migrator), 6296571943916667766527, "DAI_weweth4626Migrator");
        assertEq(DAI.balanceOf(weusdc4626Migrator), 4110209314522345174307, "DAI_weusdc4626Migrator");
        assertEq(DAI.balanceOf(webtc4626Migrator), 1091711447990678553913, "DAI_webtc4626Migrator");
        assertEq(DAI.balanceOf(weosqth4626Migrator), 152391189707076801693, "DAI_weosqth4626Migrator");
        assertEq(DAI.balanceOf(wedai4626Migrator), 639593174393075053553, "DAI_wedai4626Migrator");
        assertEq(DAI.balanceOf(welusd4626Migrator), 114610888586634740425, "DAI_welusd4626Migrator");
        
        assertEq(USDC.balanceOf(weweth4626Migrator), 485335112, "USDC_weweth4626Migrator");
        assertEq(USDC.balanceOf(weusdc4626Migrator), 316811896, "USDC_weusdc4626Migrator");
        assertEq(USDC.balanceOf(webtc4626Migrator), 84148311, "USDC_webtc4626Migrator");
        assertEq(USDC.balanceOf(weosqth4626Migrator), 11746199, "USDC_weosqth4626Migrator");
        assertEq(USDC.balanceOf(wedai4626Migrator), 49299368, "USDC_wedai4626Migrator");
        assertEq(USDC.balanceOf(welusd4626Migrator), 8834121, "USDC_welusd4626Migrator");

        assertEq(OSQTH.balanceOf(weosqth4626Migrator), 37715590842656521648, "OSQTH_weosqth4626Migrator");

        assertGt(OwnableERC4626Migrator(weweth4626Migrator).wethPerERC4626(), 0, "weweth4626Migrator_wethPerERC4626");
        assertGt(OwnableERC4626Migrator(weusdc4626Migrator).wethPerERC4626(), 0, "weusdc4626Migrator_wethPerERC4626");
        assertGt(OwnableERC4626Migrator(webtc4626Migrator).wethPerERC4626(), 0, "webtc4626Migrator_wethPerERC4626");
        assertGt(OwnableERC4626MigratorWithOSQTH(weosqth4626Migrator).wethPerERC4626(), 0, "weosqth4626Migrator_wethPerERC4626");
        assertGt(OwnableERC4626Migrator(wedai4626Migrator).wethPerERC4626(), 0, "wedai4626Migrator_wethPerERC4626");
        assertGt(OwnableERC4626Migrator(welusd4626Migrator).wethPerERC4626(), 0, "welusd4626Migrator_wethPerERC4626");

        assertEq(OwnableERC4626Migrator(weweth4626Migrator).owner(), eulerMultisig, "weweth4626Migrator_owner");
        assertEq(OwnableERC4626Migrator(weusdc4626Migrator).owner(), eulerMultisig, "weusdc4626Migrator_owner");
        assertEq(OwnableERC4626Migrator(webtc4626Migrator).owner(), eulerMultisig, "webtc4626Migrator_owner");
        assertEq(OwnableERC4626MigratorWithOSQTH(weosqth4626Migrator).owner(), eulerMultisig, "weosqth4626Migrator_owner");
        assertEq(OwnableERC4626Migrator(wedai4626Migrator).owner(), eulerMultisig, "wedai4626Migrator_owner");
        assertEq(OwnableERC4626Migrator(welusd4626Migrator).owner(), eulerMultisig, "welusd4626Migrator_owner");
    }

    function testDistributeWETHTransfer() public {
        // Mint assets to self, then transfer to the distributor
        deal(address(WETH), address(this), 26897136528044443766);
        deal(address(DAI), address(this), 12405087959116478090418);
        deal(address(USDC), address(this), 956175007);
        deal(address(OSQTH), address(this), 37715590842656521648);

        WETH.transfer(address(DISTRIBUTOR), WETH.balanceOf(address(this)));
        DAI.transfer(address(DISTRIBUTOR), DAI.balanceOf(address(this)));
        USDC.transfer(address(DISTRIBUTOR), USDC.balanceOf(address(this)));
        OSQTH.transfer(address(DISTRIBUTOR), OSQTH.balanceOf(address(this)));

        // Distribute
        vm.expectRevert("WETH balance incorrect");
        DISTRIBUTOR.distribute();
    }

    function testDistributeDAITransfer() public {
        // Mint assets to self, then transfer to the distributor
        deal(address(WETH), address(this), 26897136528044443767);
        deal(address(DAI), address(this), 12405087959116478090417);
        deal(address(USDC), address(this), 956175007);
        deal(address(OSQTH), address(this), 37715590842656521648);

        WETH.transfer(address(DISTRIBUTOR), WETH.balanceOf(address(this)));
        DAI.transfer(address(DISTRIBUTOR), DAI.balanceOf(address(this)));
        USDC.transfer(address(DISTRIBUTOR), USDC.balanceOf(address(this)));
        OSQTH.transfer(address(DISTRIBUTOR), OSQTH.balanceOf(address(this)));

        // Distribute
        vm.expectRevert("DAI balance incorrect");
        DISTRIBUTOR.distribute();
    }

    function testDistributeUSDCTransfer() public {
        // Mint assets to self, then transfer to the distributor
        deal(address(WETH), address(this), 26897136528044443767);
        deal(address(DAI), address(this), 12405087959116478090418);
        deal(address(USDC), address(this), 956175006);
        deal(address(OSQTH), address(this), 37715590842656521648);

        WETH.transfer(address(DISTRIBUTOR), WETH.balanceOf(address(this)));
        DAI.transfer(address(DISTRIBUTOR), DAI.balanceOf(address(this)));
        USDC.transfer(address(DISTRIBUTOR), USDC.balanceOf(address(this)));
        OSQTH.transfer(address(DISTRIBUTOR), OSQTH.balanceOf(address(this)));

        // Distribute
        vm.expectRevert("USDC balance incorrect");
        DISTRIBUTOR.distribute();
    }

    function testDistributeOSQTHTransfer() public {
        // Mint assets to self, then transfer to the distributor
        deal(address(WETH), address(this), 26897136528044443767);
        deal(address(DAI), address(this), 12405087959116478090418);
        deal(address(USDC), address(this), 956175007);
        deal(address(OSQTH), address(this), 37715590842656521647);

        WETH.transfer(address(DISTRIBUTOR), WETH.balanceOf(address(this)));
        DAI.transfer(address(DISTRIBUTOR), DAI.balanceOf(address(this)));
        USDC.transfer(address(DISTRIBUTOR), USDC.balanceOf(address(this)));
        OSQTH.transfer(address(DISTRIBUTOR), OSQTH.balanceOf(address(this)));

        // Distribute
        vm.expectRevert("oSQTH balance incorrect");
        DISTRIBUTOR.distribute();
    }
}
