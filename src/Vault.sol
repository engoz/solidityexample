//  SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

uint256 constant M = 2;
uint256 constant N = 3;

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
}

contract Vault {

    struct Transfer {
        address payable to;
        uint8   signs;
        uint40  execTime;
        uint40  expiration;
        address asset;
        uint40  dt;
        uint256 amount;
    }

    address[N] public  signers;
    mapping(address => uint8) public signersMasks;

    Transfer[] public transfers;
    bool private      locked;

    error TooMuchSigners();
    error InvalidSender();
    error ExpirationTooShortOrNegative();
    error SignerAlreadySigned();
    error ReentrancyAttack();
    error AlreadyExecuted();
    error Expired();
    error NotSignedByCaller();
    error TokenTransferFailed();
    error IndexOutOfBounds();

    receive() external payable {}

    modifier nonReentrant() {
        if(locked) revert ReentrancyAttack();
        locked = true;
        _;
        locked = false;
    }

    constructor(address[N] memory signers_) {
        if(N > 8)
            revert TooMuchSigners();

        for(uint I = 0; I < N; ++I) {
            signers[I] = signers_[I];
            signersMasks[signers_[I]] = uint8(1 << I);
        }
    }

    function _getSignerMask() internal view returns (uint8) {

        uint8 mask = signersMasks[msg.sender];
        if(0 == mask)
            revert InvalidSender();
        return mask;
    }

    function countSetBits(uint8 n) public pure returns (uint) {
        uint8 count;
        for (count = 0; n > 0; count++) {
            n &= (n - 1);
        }
        return uint(count);
    }

    function newTransfer(Transfer memory transfer_) external {
        uint8 signerMask = _getSignerMask();
        transfer_.signs = signerMask;
        transfer_.dt = uint40(block.timestamp);
        transfer_.execTime = 0;
        if(transfer_.expiration < 1800 + transfer_.dt)
            revert ExpirationTooShortOrNegative();
        transfers.push(transfer_);
    }

    function sign(uint256 transferIndex) external nonReentrant {
        if(transfers[transferIndex].execTime != 0)
            revert AlreadyExecuted();
        if(transfers[transferIndex].expiration < block.timestamp)
            revert Expired();
        uint8 signerMask = _getSignerMask();
        uint8 signs = transfers[transferIndex].signs;
        if(signs & signerMask != 0)
            revert SignerAlreadySigned();
        signs |= signerMask;
        transfers[transferIndex].signs = signs;
        if(countSetBits(signs) < M)
            return;

        Transfer memory transfer = transfers[transferIndex];
        if(transfer.asset == address(0)) {
            transfer.to.transfer(transfer.amount);
        }
        else {
            if(!IERC20(transfer.asset).transfer(transfer.to, transfer.amount)) revert TokenTransferFailed();
        }
        transfers[transferIndex].execTime = uint40(block.timestamp);
    }

    function revoke(uint256 transferIndex) external {
        if(transfers[transferIndex].execTime != 0)
            revert AlreadyExecuted();

        uint8 signerMask = _getSignerMask();
        uint8 signs = transfers[transferIndex].signs;
        if(signs & signerMask == 0) revert NotSignedByCaller();
        transfers[transferIndex].signs &= ~signerMask;
    }

    //  Readers
    function getTransfersLength() public view returns(uint256) {
        return transfers.length;
    }

    function getTransfers(uint256 startIndex, uint256 count) public view returns (Transfer[] memory) {
        if(startIndex >= transfers.length) revert IndexOutOfBounds();
        uint256 endIndex = startIndex + count;
        if (endIndex > transfers.length) {
            endIndex = transfers.length;
        }

        Transfer[] memory result = new Transfer[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = transfers[i];
        }

        return result;
    }
}