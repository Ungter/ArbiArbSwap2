// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {ERC20, SafeTransferLib} from "./solmate/utils/SafeTransferLib.sol";
import {UnsafeUnilib} from "./lib/UnsafeUnilib.sol";

abstract contract BaseSwapperV2 {
    using SafeTransferLib for ERC20;
    // Address is different on different chains
    address constant WETH = PLACE_HOLDER;

    function execute(address bAsset, uint256 bAmt, address rAsset, uint256 rAmt, bytes memory eData) internal virtual {}

    function swap(address bAsset, uint256 bAmt, address rAsset, bool t, bytes memory eData) public {
        if (!t) {
            _sFS(bAsset, bAmt, rAsset, eData);
        } else {
            _tFS(bAsset, bAmt, rAsset, eData);
        }
    }

    function _sFS(address bAsset, uint256 bAmt, address rAsset, bytes memory eData) private {
        (address t0, address t1, uint256 a0Out, uint256 a1Out) = bAsset < rAsset 
            ? (bAsset, rAsset, bAmt, uint256(0)) 
            : (rAsset, bAsset, uint256(0), bAmt);
        bytes memory data = abi.encode(bAsset, bAmt, rAsset, 0, eData);
        address pair = UnsafeUnilib.getPair(t0, t1);
        IUniswapV2Pair(pair).swap(a0Out, a1Out, address(this), data);
    }

    function _tFS(address bAsset, uint256 bAmt, address rAsset, bytes memory eData) private {
        (address bPair, uint256 wethN) = _cIA(WETH, bAsset, bAmt);
        bytes memory data = abi.encode(bAsset, bAmt, rAsset, wethN, eData);
        (uint256 a0Out, uint256 a1Out, address t0, address t1) = rAsset < WETH 
            ? (uint256(0), wethN, rAsset, WETH) 
            : (wethN, uint256(0), WETH, rAsset);
        address rPair = UnsafeUnilib.getPair(t0, t1);
        IUniswapV2Pair(rPair).swap(a0Out, a1Out, address(this), data);
    }

    function _tE(address bAsset, uint256 bAmt, address rAsset, uint256 wethR, bytes memory eData) private {
        (address t0, address t1, uint256 a0Out, uint256 a1Out) = bAsset < WETH
            ? (bAsset, WETH, bAmt, uint256(0))
            : (WETH, bAsset, uint256(0), bAmt);
        address bPair = UnsafeUnilib.getPair(t0, t1);

        // Pay WETH to bPair and get bAmt of bAsset
        ERC20(WETH).safeTransfer(bPair, wethR);
        IUniswapV2Pair(bPair).swap(a0Out, a1Out, address(this), bytes(""));

        (address rPair, uint256 amtToR) = _cIA(rAsset, WETH, wethR);
        
        execute(bAsset, bAmt, rAsset, amtToR, eData);

        // Repay the rPair flash swap with rAsset
        ERC20(rAsset).safeTransfer(rPair, amtToR);
    }

    function _sE(address bAsset, uint256 bAmt, address rAsset, bytes memory eData) private {
        (address pair, uint256 rAmt) = _cIA(rAsset, bAsset, bAmt);
        
        execute(bAsset, bAmt, rAsset, rAmt, eData);

        // Repay pair flash swap with rAsset
        ERC20(rAsset).safeTransfer(pair, rAmt);
    }

    function _cIA(address iAsset, address oAsset, uint256 oAmt) private view returns (address pair, uint256 iAmt) {
        pair = UnsafeUnilib.sortAndGetPair(iAsset, oAsset);
        (uint112 r0, uint112 r1, ) = IUniswapV2Pair(pair).getReserves();
        (uint256 iR, uint256 oR) = iAsset < oAsset ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));
        // Standard Uniswap formula for given output: iAmt = ((1000 * iR * oAmt) / (997 * (oR - oAmt))) + 1;
        iAmt = ((1000 * iR * oAmt) / (997 * (oR - oAmt))) + 1;
    }

    // Loaned flash
    function uniswapV2Call(address sender, uint256 a0, uint256 a1, bytes calldata d) external {
        (address bAsset, uint256 bAmt, address rAsset, uint256 wethI, bytes memory eData) = 
            abi.decode(d, (address, uint256, address, uint256, bytes));
        
        if (wethI > 0) {
            _tE(bAsset, bAmt, rAsset, wethI, eData);
        } else {
            _sE(bAsset, bAmt, rAsset, eData);
        }
    }
}
