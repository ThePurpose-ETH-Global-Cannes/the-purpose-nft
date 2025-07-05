// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract WinnerTakeAllPool5Level {

    IERC20 public immutable token;
    address public owner;

    uint256 public gameEndTime;
    uint256 internal totalPool;
    address internal winner;
    uint256 public stakeSize = 10; // Need to clarify later

    enum RequestStatus { None, Pending, Accepted, Rejected }

    mapping(address => mapping(address => RequestStatus)) public requestStatus;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not an owner.");
        _;
    }

    //mapping(address => address[]) public mutualConnections;
    //mapping(address => address[]) public connectionsRequests;

    mapping(address => mapping(address => bool)) public mutualConnections;
    mapping(address => mapping(address => bool)) public connectionRequests;
    mapping(address => address[]) public connectionRequestsList;

    mapping(address => uint256) public deposits;
    address[] public participants;

    event GameStarted(uint256 endTime);
    event Deposited(address indexed user, uint256 amount, string domain);
    event WinnerSelected(address indexed winner);
    event TotalPrizeClaimed(address indexed winner, uint256 amount);
    event SingleShareOfPrizeClaimed(address indexed shareReceiver, uint256 amount);
    
    event ConnectionRequestSent(address indexed from, address indexed to);
    event ConnectionAccepted(address indexed from, address indexed to);
    event ConnectionRejected(address indexed from, address indexed to);
    event ConnectionRemoved(address indexed from, address indexed to);
    event ConnectionAdded(address indexed user, address indexed connection);

    bool eventGameStartedEmittedOnce = false;

    error GameAlreadyStarted();

    constructor(address _tokenAddress) {
        token = IERC20(_tokenAddress);
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
        require(block.timestamp <= gameEndTime, "The game has ended.");
        require(gameEndTime > block.timestamp, "The game is not started or already ended.");
        require(deposits[msg.sender] <= 10, "Can not stake more than once.");                                                 // ToDo: Need checking later

        if (deposits[msg.sender] == 0) {
            participants.push(msg.sender);
        }

        deposits[msg.sender] += stakeSize;
        totalPool += stakeSize;
        token.transferFrom(msg.sender, address(this), stakeSize);

        emit Deposited(msg.sender, stakeSize, _domain);
    }

    function selectWinner() external {
        require (block.timestamp > gameEndTime, "The game has not ended yet.");
        require (winner != address(0), "Invalid address.");
        require (participants.length != 0, "No participants to choose a winner from.");

        uint256 winningTicket = _getRandomNumber(participants.length);
        uint256 currentTicket = 0;

        for (uint256 i = 0; i < participants.length; i++) {
            address currentUser = participants[i];
            currentTicket += deposits[currentUser];
            if (winningTicket < currentTicket) {
                winner = currentUser;
                emit WinnerSelected(winner);
                return;
            }
        }
    }

    function claimPrize() external {
        require(msg.sender == winner, "Not a winner.");
        require(totalPool != 0, "Prize is already claimed.");

        uint256 mutualConnectionsCount = 0;
        for (address connection : connectionRequestsList[winner]) {
            if (mutualConnections[winner][connection]) {
                mutualConnectionsCount++;
            }
        }
        uint256 prizeAmount = totalPool;
        uint256 prizePerUser = prizeAmount / mutualConnectionsCount;
        totalPool = 0; // Prevent re-entrancy

        uint256 distributedToConnections = 0;
        for (address connection : connectionRequestsList[winner]) {
            if (mutualConnections[winner][connection]) {
                token.transfer(connection, prizePerUser);
                distributedToConnections += prizePerUser;
                emit SingleShareOfPrizeClaimed(connection, prizePerUser);
            }
        }
        uint256 winnerPrize = prizeAmount - distributedToConnections;
        token.transfer(winner, winnerPrize);

        emit TotalPrizeClaimed(winner, prizeAmount);
        
        // Reset game state for the next round.
        eventGameStartedEmittedOnce = false;
    }

    // Service functions
    
    function _getRandomNumber(uint256 _participantsCount) private view returns (uint256) {
        uint256 random = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, participants.length)));
        return random % _participantsCount;
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
}
