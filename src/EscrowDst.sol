// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title EscrowDst
 * @dev Destination escrow contract for 1inch Fusion+ cross-chain swaps
 * This contract is deployed as a clone for each swap on the destination chain
 */
contract EscrowDst is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Events
    event EscrowInitialized(
        address indexed token,
        uint256 amount,
        address indexed recipient,
        bytes32 hashlock,
        uint256 timelock
    );

    event Withdrawal(
        address indexed recipient,
        uint256 amount,
        bytes32 secret
    );

    event Cancellation(
        address indexed canceller,
        uint256 amount
    );

    // Immutable state variables (set during construction)
    address public immutable token;
    uint256 public immutable amount;
    address public immutable recipient;
    bytes32 public immutable hashlock;
    uint256 public immutable timelock;
    uint256 public immutable createdAt;

    // Mutable state variables
    bool public isWithdrawn;
    bool public isCancelled;

    // Modifiers
    modifier notWithdrawn() {
        require(!isWithdrawn, "EscrowDst: Already withdrawn");
        _;
    }

    modifier notCancelled() {
        require(!isCancelled, "EscrowDst: Already cancelled");
        _;
    }

    modifier validSecret(bytes32 secret) {
        require(keccak256(abi.encodePacked(secret)) == hashlock, "EscrowDst: Invalid secret");
        _;
    }

    modifier timelockExpired() {
        require(block.timestamp > createdAt + timelock, "EscrowDst: Timelock not expired");
        _;
    }

    /**
     * @dev Constructor for EscrowDst clone
     * @param _token Token address (address(0) for native)
     * @param _amount Amount to escrow
     * @param _recipient Recipient address
     * @param _hashlock Hash of the secret
     * @param _timelock Timelock duration
     */
    constructor(
        address _token,
        uint256 _amount,
        address _recipient,
        bytes32 _hashlock,
        uint256 _timelock
    ) Ownable(msg.sender) {
        require(_amount > 0, "EscrowDst: Invalid amount");
        require(_recipient != address(0), "EscrowDst: Invalid recipient");
        require(_timelock > 0, "EscrowDst: Invalid timelock");

        token = _token;
        amount = _amount;
        recipient = _recipient;
        hashlock = _hashlock;
        timelock = _timelock;
        createdAt = block.timestamp;

        emit EscrowInitialized(_token, _amount, _recipient, _hashlock, _timelock);
    }

    /**
     * @dev Withdraw tokens using secret
     * @param secret Secret to unlock escrow
     */
    function withdraw(bytes32 secret) 
        external 
        nonReentrant 
        notWithdrawn 
        notCancelled 
        validSecret(secret)
    {
        isWithdrawn = true;

        _transferTokens(recipient, amount);

        emit Withdrawal(recipient, amount, secret);
    }

    /**
     * @dev Cancel escrow after timelock expires
     */
    function cancel() 
        external 
        onlyOwner 
        notWithdrawn 
        notCancelled 
        timelockExpired
    {
        isCancelled = true;

        _transferTokens(owner(), amount);

        emit Cancellation(msg.sender, amount);
    }

    /**
     * @dev Public withdrawal after timelock expires
     * @param secret Secret to unlock escrow
     */
    function publicWithdraw(bytes32 secret) 
        external 
        nonReentrant 
        notWithdrawn 
        notCancelled 
        validSecret(secret) 
        timelockExpired
    {
        isWithdrawn = true;

        _transferTokens(msg.sender, amount);

        emit Withdrawal(msg.sender, amount, secret);
    }

    /**
     * @dev Transfer tokens (ERC20 or native)
     * @param to Recipient
     * @param transferAmount Amount to transfer
     */
    function _transferTokens(address to, uint256 transferAmount) internal {
        if (token == address(0)) {
            payable(to).transfer(transferAmount);
        } else {
            IERC20(token).safeTransfer(to, transferAmount);
        }
    }

    // View functions
    function isExpired() external view returns (bool) {
        return block.timestamp > createdAt + timelock;
    }

    function getStatus() external view returns (bool withdrawn, bool cancelled, bool expired) {
        return (isWithdrawn, isCancelled, block.timestamp > createdAt + timelock);
    }

    // Emergency functions
    function emergencyWithdraw() external onlyOwner {
        require(block.timestamp > createdAt + timelock + 1 days, "EscrowDst: Too early for emergency");
        _transferTokens(owner(), address(this).balance);
    }

    receive() external payable {}
} 