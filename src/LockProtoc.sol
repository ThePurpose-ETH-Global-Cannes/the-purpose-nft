// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract WinnerTakeAllPool5Level {

    IERC20 public immutable usdcToken; // USDC on Flow
    address public owner;

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

    mapping(address => uint256) public deposits;
    address[] public participants;

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

    constructor(address _tokenAddress) {
        usdcToken = IERC20(_tokenAddress);
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
        require(bytes(_domain).length != 0, "Domain can not be empty.");
        require(block.timestamp <= gameEndTime[roundId], "The game has ended.");
        require(gameEndTime[roundId] > block.timestamp, "The game is not started or already ended.");
        require(deposits[msg.sender] <= stakeSize, "Can not stake more than once.");                                         // ToDo: Need to clarify      

        if (deposits[msg.sender] == 0) {
            participants.push(msg.sender);
        }

        deposits[msg.sender] += stakeSize;
        totalPool[roundId] += stakeSize;
        usdcToken.transferFrom(msg.sender, address(this), stakeSize);

        emit Deposited(msg.sender, stakeSize, _domain);
    }

    function selectWinner() external {
        require(block.timestamp > gameEndTime[roundId], "The game has not ended yet.");
        require(winner[roundId] == address(0), "Winner has already been selected.");
        require(participants.length != 0, "No participants to choose a winner from.");

        uint256 winningIndex = _getRandomNumber(participants.length);
        winner[roundId] = participants[winningIndex];
        emit WinnerSelected(winner[roundId]);
    }

    function emergencyWithdraw(uint256 _roundId) external onlyOwner {
        require(block.timestamp > gameEndTime[_roundId], "The game has not ended yet.");
        require(winner[_roundId] == address(0), "Winner has not been selected yet.");
        require(totalPool[_roundId] != 0, "Prize is already claimed.");
        
        for (uint256 i = 0; i < participants.length; i++) {
            address currentUser = participants[i];
            usdcToken.transfer(currentUser, deposits[currentUser]);
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
                emit SingleShareOfPrizeClaimed(connection, prizePerShare);
            }
        }
        uint256 winnerPrize = prizeAmount - distributedToConnections;
        usdcToken.transfer(winner[roundId], winnerPrize);
        emit TotalPrizeClaimed(winner[roundId], prizeAmount);
        
        // Reset game state for the next round.
        eventGameStartedEmittedOnce = false;
    }

    // Service functions
    
    function _getRandomNumber(uint256 _participantsCount) private view returns (uint256) {
        (bool ok, bytes memory data) = cadenceArch.staticcall(abi.encodeWithSignature("revertibleRandom()"));
        require(ok, "Failed to fetch a random number through Cadence Arch");
        
        uint64 randomNumber = abi.decode(data, (uint64));

        return randomNumber % _participantsCount;
    }

    function getParticipants() external view returns (address[] memory) {
        return participants;
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
        // Clear participants array
        delete participants;
        
        // Reset deposits for all users (or track per round)
        // This depends on whether you want deposits to carry over
        
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
}
