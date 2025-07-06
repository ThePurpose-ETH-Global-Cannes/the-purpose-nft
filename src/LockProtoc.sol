// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ThePurpose.sol";

contract WinnerTakeAllPool5Level {

    ThePurpose public transformationNFT;
    IERC20 public immutable usdcToken; // USDC on Flow
    address public owner;
    address public nftMintApprover;

    uint256 public roundId;

    uint256 public constant MAX_CONNECTIONS = 20;

    address constant public cadenceArch = 0x0000000000000000000000010000000000000001;
    
    

    //uint256 public gameEndTime;
    mapping(uint256 => uint256) public gameEndTime;
    //uint256 internal totalPool;
    mapping(uint256 => uint256) internal totalPool;
    //address internal winner;
    mapping(uint256 => address) internal winner;
    uint256 public stakeSize = 10;                                                                              // ToDo: Need to clarify later

    enum RequestStatus { None, Pending, Accepted, Rejected }

    mapping(address => mapping(address => RequestStatus)) public requestStatus;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not an owner.");
        _;
    }

    mapping(address => mapping(address => bool)) public mutualConnections;
    mapping(address => mapping(address => bool)) public connectionRequests;
    mapping(address => address[]) public connectionRequestsList;
    mapping(uint256 => mapping(address => uint256)) public depositsPerRound;

    mapping(uint256 => mapping(address => uint256)) public deposits; // roundId => user => amount
    mapping(uint256 => address[]) public participants; // roundId => participants

    event GameStarted(uint256 indexed roundId, uint256 endTime);
    event Deposited(uint256 indexed roundId, address indexed user, uint256 amount, string domain);
    event WinnerSelected(uint256 indexed roundId, address indexed winner);
    event TotalPrizeClaimed(uint256 indexed roundId, address indexed winner, uint256 amount);
    event SingleShareOfPrizeClaimed(uint256 indexed roundId, address indexed shareReceiver, uint256 amount);
    
    event ConnectionRequestSent(address indexed from, address indexed to);
    event ConnectionAccepted(address indexed from, address indexed to);
    event ConnectionRejected(address indexed from, address indexed to);
    event ConnectionRemoved(address indexed from, address indexed to);
    event ConnectionAdded(address indexed user, address indexed connection);

    bool eventGameStartedEmittedOnce = false;

    error GameAlreadyStarted();

    // XP and Level tracking per round
    mapping(uint256 => mapping(address => uint256)) public playerXP; // roundId => player => XP
    mapping(uint256 => mapping(address => uint256)) public playerLevel; // roundId => player => level

    // 7 levels with your exact XP requirements
    uint256[] public xpRequirements = [
        0,    // Level 1 (starting level) - 0 XP
        50,   // Level 2 - 50 XP total
        75,   // Level 3 - 75 XP total
        150,  // Level 4 - 150 XP total
        300,  // Level 5 - 300 XP total
        600,  // Level 6 - 600 XP total
        1200  // Level 7 - 1200 XP total (MAX_LEVEL)
    ];

    // Maximum level
    uint256 public constant MAX_LEVEL = 7;

    // Task completion events
    event TaskCompleted(uint256 indexed roundId, address indexed player, string taskType, uint256 xpReward, uint256 totalXP, uint256 level);
    event XPAdded(uint256 indexed roundId, address indexed player, uint256 xpAdded, uint256 totalXP, uint256 level);

    // Add these missing variables:
    mapping(address => bool) public transformationCompleted;
    mapping(address => uint256) public playerNFTTokenId;
    mapping(address => bool) public bigCryptoRewardClaimed;
    uint256 public constant BIG_CRYPTO_REWARD = 1000; // 1000 USDC

    // Add missing events:
    event TransformationCompleted(address indexed player, uint256 tokenId);
    event BigCryptoRewardClaimed(address indexed player, uint256 amount);

    // Add reentrancy protection
    bool private _isReentrant;

    constructor(address _tokenAddress, address _nftContract, address _nftMintApprover) {
        usdcToken = IERC20(_tokenAddress);
        transformationNFT = ThePurpose(_nftContract);
        nftMintApprover = _nftMintApprover;
        owner = msg.sender;
    }

    function sendConnectionRequest(address _toConnectWith) external {
        require(_toConnectWith != msg.sender, "Cannot connect to self");
        require(_toConnectWith != address(0), "Invalid address");
        require(requestStatus[msg.sender][_toConnectWith] == RequestStatus.None, "Request already exists");
        
        requestStatus[msg.sender][_toConnectWith] = RequestStatus.Pending;
        connectionRequestsList[_toConnectWith].push(msg.sender);
        
        emit ConnectionRequestSent(msg.sender, _toConnectWith);
    }

    function getPendingRequests(address _user) external view returns (address[] memory) {
        address[] storage requests = connectionRequestsList[_user];
        uint256 pendingCount = 0;
        
        // First pass: count pending requests
        for (uint256 i = 0; i < requests.length; i++) {
            if (requestStatus[requests[i]][_user] == RequestStatus.Pending) {
                pendingCount++;
            }
        }
        
        // Create array with exact size
        address[] memory pendingRequests = new address[](pendingCount);
        uint256 index = 0;

        // Second pass: populate array
        for (uint256 i = 0; i < requests.length; i++) {
            if (requestStatus[requests[i]][_user] == RequestStatus.Pending) {
                pendingRequests[index] = requests[i];
                index++;
            }
        }
        
        return pendingRequests;
    }

    function acceptConnectionRequest(address _from) external {
        require(requestStatus[_from][msg.sender] == RequestStatus.Pending, "No pending request");
        
        // Check if accepting would exceed 20 connections for either user
        uint256 currentConnections = getConnectionCount(msg.sender);
        uint256 fromConnections = getConnectionCount(_from);
        
        require(currentConnections < 20, "You cannot have more than 20 connections");
        require(fromConnections < 20, "User cannot have more than 20 connections");
        
        requestStatus[_from][msg.sender] = RequestStatus.Accepted;
        mutualConnections[_from][msg.sender] = true;
        mutualConnections[msg.sender][_from] = true;
        
        emit ConnectionAccepted(_from, msg.sender);
    }

    function rejectConnectionRequest(address _from) external {
        require(requestStatus[_from][msg.sender] == RequestStatus.Pending, "No pending request");
        
        requestStatus[_from][msg.sender] = RequestStatus.Rejected;
        
        emit ConnectionRejected(_from, msg.sender);
    }

    function removeConnection(address _toRemove) external {
        require(mutualConnections[msg.sender][_toRemove], "No connection exists");
        
        mutualConnections[msg.sender][_toRemove] = false;
        mutualConnections[_toRemove][msg.sender] = false;
        
        emit ConnectionRemoved(msg.sender, _toRemove);
    }

    function getConnections(address _user) external view returns (address[] memory) {
        address[] storage allRequests = connectionRequestsList[_user];
        uint256 connectionCount = 0;
        
        // First pass: count connections
        for (uint256 i = 0; i < allRequests.length; i++) {
            if (mutualConnections[_user][allRequests[i]]) {
                connectionCount++;
            }
        }
        
        // Create array with exact size
        address[] memory connections = new address[](connectionCount);
        uint256 index = 0;
        
        // Second pass: populate array
        for (uint256 i = 0; i < allRequests.length; i++) {
            if (mutualConnections[_user][allRequests[i]]) {
                connections[index] = allRequests[i];
                index++;
            }
        }
        
        return connections;
    }

    function startGame(uint256 _duration) external onlyOwner {
        require(eventGameStartedEmittedOnce == false, "The game has been started.");

        gameEndTime = block.timestamp + _duration;
        emit GameStarted(gameEndTime);
        eventGameStartedEmittedOnce = true;
    }

    function deposit(string memory _domain) external {
        require(roundId > 0, "Round not initialized");
        require(bytes(_domain).length != 0, "Domain can not be empty.");
        require(block.timestamp <= gameEndTime[roundId], "The game has ended.");
        require(gameEndTime[roundId] > block.timestamp, "The game is not started or already ended.");
        
        // Auto-initialize player if first time
        if (playerLevel[roundId][msg.sender] == 0) {
            playerLevel[roundId][msg.sender] = 1;
            playerXP[roundId][msg.sender] = 0;
        }
        
        uint256 currentLevel = playerLevel[roundId][msg.sender];
        require(currentLevel == 4, "Only Level 4 users can stake");
        
        // Level 4 deposits fixed stakeSize amount
        require(deposits[roundId][msg.sender] <= stakeSize, "Can not stake more than once.");

        if (deposits[roundId][msg.sender] == 0) {
            participants[roundId].push(msg.sender);
        }

        deposits[roundId][msg.sender] += stakeSize;
        totalPool[roundId] += stakeSize;
        usdcToken.transferFrom(msg.sender, address(this), stakeSize);

        // No XP from staking - XP comes from frontend-triggered tasks
        emit Deposited(roundId, msg.sender, stakeSize, _domain);
    }

    function selectWinner() external {
        require(block.timestamp > gameEndTime[roundId], "The game has not ended yet.");
        require(winner[roundId] == address(0), "Winner has already been selected.");
        require(participants[roundId].length != 0, "No participants to choose a winner from.");

        uint256 winningIndex = _getRandomNumber(participants[roundId].length);
        winner[roundId] = participants[roundId][winningIndex];
        emit WinnerSelected(roundId, winner[roundId]);
    }

    function emergencyWithdraw(uint256 _roundId) external onlyOwner {
        require(block.timestamp > gameEndTime[_roundId], "The game has not ended yet.");
        require(winner[_roundId] == address(0), "Winner has not been selected yet.");
        require(totalPool[_roundId] != 0, "Prize is already claimed.");
        
        for (uint256 i = 0; i < participants[_roundId].length; i++) {
            address currentUser = participants[_roundId][i];
            usdcToken.transfer(currentUser, deposits[_roundId][currentUser]);
        }

        totalPool[_roundId] = 0;
    }

    function claimPrize() external {
        require(msg.sender == winner[roundId], "Not a winner.");
        require(totalPool[roundId] != 0, "Prize is already claimed.");

        uint256 mutualConnectionsCount = 0;
        for (address connection : connectionRequestsList[winner[roundId]]) {
            if (mutualConnections[winner[roundId]][connection]) {
                mutualConnectionsCount++;
            }
        }
        uint256 prizeAmount = totalPool[roundId];
        totalPool[roundId] = 0; // Prevent re-entrancy

        uint256 totalRecipients = mutualConnectionsCount + 1; // +1 for winner and to prevent possible division by zero
        uint256 prizePerShare = prizeAmount / totalRecipients;

        uint256 distributedToConnections = 0;
        for (address connection : connectionRequestsList[winner[roundId]]) {
            if (mutualConnections[winner[roundId]][connection]) {
                usdcToken.transfer(connection, prizePerShare);
                distributedToConnections += prizePerShare;
                emit SingleShareOfPrizeClaimed(roundId, connection, prizePerShare);
            }
        }
        uint256 winnerPrize = prizeAmount - distributedToConnections;
        usdcToken.transfer(winner[roundId], winnerPrize);
        emit TotalPrizeClaimed(roundId, winner[roundId], prizeAmount);
        
        // Reset game state for the next round.
        eventGameStartedEmittedOnce = false;
    }

    function completeTransformation(uint256 blockNumber, bytes calldata signature) external {
        require(playerLevel[roundId][msg.sender] >= 7, "Must reach Level 7 to complete transformation");
        require(!transformationCompleted[msg.sender], "Transformation already completed");
        
        // Add reentrancy protection
        require(!_isReentrant, "Reentrant call");
        _isReentrant = true;
        
        transformationCompleted[msg.sender] = true;
        
        // Mint NFT using the local contract
        transformationNFT.mint(blockNumber, signature);
        
        // Track token ID
        uint256 tokenId = transformationNFT.totalSupply() - 1;
        playerNFTTokenId[msg.sender] = tokenId;
        
        // Claim BIG crypto reward automatically
        if (!bigCryptoRewardClaimed[msg.sender]) {
            bigCryptoRewardClaimed[msg.sender] = true;
            usdcToken.transfer(msg.sender, BIG_CRYPTO_REWARD);
            emit BigCryptoRewardClaimed(msg.sender, BIG_CRYPTO_REWARD);
        }
        
        emit TransformationCompleted(msg.sender, tokenId);
        _isReentrant = false;
    }

    // Service functions
    
    function _getRandomNumber(uint256 _participantsCount) private view returns (uint256) {
        (bool ok, bytes memory data) = cadenceArch.staticcall(abi.encodeWithSignature("revertibleRandom()"));
        require(ok, "Failed to fetch a random number through Cadence Arch");
        
        uint64 randomNumber = abi.decode(data, (uint64));

        return randomNumber % _participantsCount;
    }

    function getParticipants() external view returns (address[] memory) {
        return participants[roundId];
    }

    function isTheGameIsOn() external view returns (bool) {
        return gameEndTime != 0 && block.timestamp < gameEndTime;
    }

    function addConnection(address _user, address _connection) external {
        mutualConnections[_user][_connection] = true;
        emit ConnectionAdded(_user, _connection);
    }

    // Return all requests (frontend can filter)
    function getConnectionRequestsList(address _user) external view returns (address[] storage) {
        return connectionRequestsList[_user];
    }

    // Frontend can check status with this function
    function getRequestStatus(address _from, address _to) external view returns (RequestStatus) {
        return requestStatus[_from][_to];
    }

    // Check if connected
    function areConnected(address _user1, address _user2) external view returns (bool) {
        return mutualConnections[_user1][_user2];
    }

    // Get connection count
    function getConnectionCount(address _user) external view returns (uint256) {
        uint256 count = 0;
        address[] storage requests = connectionRequestsList[_user];
        for (uint256 i = 0; i < requests.length; i++) {
            if (mutualConnections[_user][requests[i]]) {
                count++;
            }
        }
        return count;
    }

    // Start a new round
    function startNewRound(uint256 _duration) external onlyOwner {
        roundId++;
        gameEndTime[roundId] = block.timestamp + _duration;
        eventGameStartedEmittedOnce = false; // Reset for new round
        emit GameStarted(gameEndTime[roundId]);
    }

    // Get current round info
    function getCurrentRound() external view returns (uint256) {
        return roundId;
    }

    // Check if current round is active
    function isCurrentRoundActive() external view returns (bool) {
        return gameEndTime[roundId] != 0 && block.timestamp < gameEndTime[roundId];
    }

    // Reset game state for new round
    function resetForNewRound() external onlyOwner {
        // Store participants before deletion
        address[] memory currentParticipants = participants[roundId];
        
        // Clear participants array for current round
        delete participants[roundId];
        
        // Reset deposits for current round
        for (uint256 i = 0; i < currentParticipants.length; i++) {
            deposits[roundId][currentParticipants[i]] = 0;
        }
        
        // Reset winner for current round
        winner[roundId] = address(0);
        
        // Reset total pool for current round
        totalPool[roundId] = 0;
    }

    // Get winner of specific round
    function getWinner(uint256 _roundId) external view returns (address) {
        return winner[_roundId];
    }

    // Get total pool of specific round
    function getTotalPool(uint256 _roundId) external view returns (uint256) {
        return totalPool[_roundId];
    }

    // Get game end time of specific round
    function getGameEndTime(uint256 _roundId) external view returns (uint256) {
        return gameEndTime[_roundId];
    }

    // Check if specific round is active
    function isRoundActive(uint256 _roundId) external view returns (bool) {
        return gameEndTime[_roundId] != 0 && block.timestamp < gameEndTime[_roundId];
    }

    // Optional: Track connections per round
    mapping(uint256 => mapping(address => mapping(address => bool))) public mutualConnectionsPerRound;

    // Add XP to reach next level (called from frontend)
    function addXPToNextLevel(address _player) external onlyOwner {
        uint256 currentXP = playerXP[roundId][_player];
        uint256 currentLevel = playerLevel[roundId][_player];
        
        // Check if player can level up
        if (currentLevel >= MAX_LEVEL) {
            emit XPAdded(roundId, _player, 0, currentXP, currentLevel);
            return; // Already at max level
        }
        
        // Calculate XP needed for next level
        uint256 xpNeededForNextLevel = xpRequirements[currentLevel];
        uint256 xpDeficit = xpNeededForNextLevel - currentXP;
        
        if (xpDeficit > 0) {
            playerXP[roundId][_player] += xpDeficit;
            _checkAndUpdateLevel(_player);
            emit XPAdded(roundId, _player, xpDeficit, playerXP[roundId][_player], playerLevel[roundId][_player]);
        }
    }

    // Complete task and add XP based on level requirements
    function completeTask(address _player, string memory _taskType) external onlyOwner {
        uint256 currentXP = playerXP[roundId][_player];
        uint256 currentLevel = playerLevel[roundId][_player];
        
        // Get base XP reward for task type
        uint256 baseXPReward = _getTaskXPReward(_taskType);
        
        // Calculate XP needed for next level
        uint256 xpNeededForNextLevel = 0;
        if (currentLevel < MAX_LEVEL) {
            xpNeededForNextLevel = xpRequirements[currentLevel];
        }
        
        // Calculate how much XP to add
        uint256 xpToAdd = 0;
        if (currentLevel < MAX_LEVEL) {
            uint256 xpDeficit = xpNeededForNextLevel - currentXP;
            xpToAdd = xpDeficit > 0 ? xpDeficit : baseXPReward;
        } else {
            xpToAdd = baseXPReward; // At max level, just add base reward
        }
        
        playerXP[roundId][_player] += xpToAdd;
        _checkAndUpdateLevel(_player);
        
        emit TaskCompleted(roundId, _player, _taskType, xpToAdd, playerXP[roundId][_player], playerLevel[roundId][_player]);
    }

    // Get XP needed for next level
    function getXPNeededForNextLevel(address _player) external view returns (uint256) {
        uint256 currentLevel = playerLevel[roundId][_player];
        if (currentLevel >= MAX_LEVEL) {
            return 0; // Already at max level
        }
        
        uint256 currentXP = playerXP[roundId][_player];
        uint256 xpNeededForNextLevel = xpRequirements[currentLevel];
        uint256 xpDeficit = xpNeededForNextLevel - currentXP;
        
        return xpDeficit > 0 ? xpDeficit : 0;
    }

    // Get player's progress info
    function getPlayerProgress(address _player) external view returns (
        uint256 currentXP,
        uint256 currentLevel,
        uint256 xpNeededForNextLevel,
        uint256 progress,
        bool canLevelUp
    ) {
        currentXP = playerXP[roundId][_player];
        currentLevel = playerLevel[roundId][_player];
        xpNeededForNextLevel = getXPNeededForNextLevel(_player);
        
        if (currentLevel >= MAX_LEVEL) {
            progress = 100;
            canLevelUp = false;
        } else {
            uint256 xpForCurrentLevel = xpRequirements[currentLevel - 1];
            uint256 xpForNextLevel = xpRequirements[currentLevel];
            uint256 xpNeeded = xpForNextLevel - xpForCurrentLevel;
            uint256 xpProgress = currentXP - xpForCurrentLevel;
            
            progress = (xpProgress * 100) / xpNeeded;
            canLevelUp = currentXP >= xpForNextLevel;
        }
    }

    // Add this function to initialize new players
    function initializePlayer(address _player) external onlyOwner {
        if (playerLevel[roundId][_player] == 0) {
            playerLevel[roundId][_player] = 1;
            playerXP[roundId][_player] = 0;
        }
    }

    function _checkAndUpdateLevel(address _player) private {
        uint256 currentXP = playerXP[roundId][_player];
        uint256 currentLevel = playerLevel[roundId][_player];
        
        // Ensure player is initialized
        if (currentLevel == 0) {
            playerLevel[roundId][_player] = 1;
            currentLevel = 1;
        }
        
        // Check if player can level up
        for (uint256 level = currentLevel + 1; level <= MAX_LEVEL; level++) {
            if (currentXP >= xpRequirements[level - 1]) {
                playerLevel[roundId][_player] = level;
            } else {
                break;
            }
        }
    }

    function _getTaskXPReward(string memory _taskType) private pure returns (uint256) {
        // Convert to lowercase for consistent comparison
        bytes memory taskBytes = bytes(_taskType);
        bytes memory lowerTask = new bytes(taskBytes.length);
        
        for (uint256 i = 0; i < taskBytes.length; i++) {
            if (taskBytes[i] >= 0x41 && taskBytes[i] <= 0x5A) { // A-Z
                lowerTask[i] = bytes1(uint8(taskBytes[i]) + 32); // Convert to lowercase
            } else {
                lowerTask[i] = taskBytes[i];
            }
        }
        
        string memory lowerTaskType = string(lowerTask);
        
        // Define XP rewards for different task types
        if (keccak256(abi.encodePacked(lowerTaskType)) == keccak256(abi.encodePacked("daily"))) {
            return 10;
        } else if (keccak256(abi.encodePacked(lowerTaskType)) == keccak256(abi.encodePacked("weekly"))) {
            return 50;
        } else if (keccak256(abi.encodePacked(lowerTaskType)) == keccak256(abi.encodePacked("monthly"))) {
            return 200;
        } else {
            return 5; // Default reward
        }
    }

    // Add migration function for existing data
    function migrateDeposits(address[] memory _users, uint256[] memory _amounts) external onlyOwner {
        require(_users.length == _amounts.length, "Arrays length mismatch");
        for (uint256 i = 0; i < _users.length; i++) {
            deposits[roundId][_users[i]] = _amounts[i];
        }
    }

    // Add function to check if round exists
    function roundExists(uint256 _roundId) external view returns (bool) {
        return gameEndTime[_roundId] != 0;
    }

    // Add function to get round info
    function getRoundInfo(uint256 _roundId) external view returns (
        uint256 endTime,
        uint256 totalPool,
        address winner,
        uint256 participantCount
    ) {
        endTime = gameEndTime[_roundId];
        totalPool = totalPool[_roundId];
        winner = winner[_roundId];
        participantCount = participants[_roundId].length;
    }
}