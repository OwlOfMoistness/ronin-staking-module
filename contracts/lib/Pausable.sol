// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */

import "@openzeppelin/access/Ownable.sol";

error ErrPaused();

abstract contract Pausable is Ownable {
	bool public paused;

	modifier whenNotPaused() {
		if (paused) revert ErrPaused();
		_;
	}

	function pause() external onlyOwner {
		paused = true;
	}

	function unpause() external onlyOwner {
		paused = false;
	}
}