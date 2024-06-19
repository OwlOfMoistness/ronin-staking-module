// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
/*
 *     ,_,
 *    (',')
 *    {/"\}
 *    -"-"-
 */

interface IRoninGateway {
	enum Standard {
		ERC20,
		ERC721
	}

	enum Kind {
		Deposit,
		Withdrawal
	}

	struct Info {
		Standard erc;
		// For ERC20:  the id must be 0 and the quantity is larger than 0.
		// For ERC721: the quantity must be 0.
		uint256 id;
		uint256 quantity;
	}

	struct Owner {
		address addr;
		address tokenAddr;
		uint256 chainId;
	}

	struct Request {
    	address recipientAddr;
    	address tokenAddr;
    	Info info;
	}

	struct Receipt {
		uint256 id;
		Kind kind;
		Owner mainchain;
		Owner ronin;
		Info info;
	}

	struct Signature {
		uint8 v;
		bytes32 r;
		bytes32 s;
	}

	function requestEther(uint256 _amount) external;
	function getContract(uint8) external view returns(address);
	function requestWithdrawalFor(Request memory _request, uint256 _chainId) external;
	function requestDepositFor(Request calldata _request) external payable;
	function submitWithdrawal(Receipt calldata _receipt, Signature[] calldata _signatures) external returns (bool);
}