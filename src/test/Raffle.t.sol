// SPDX-License-Identifier: MIT

pragma solidity ^0.8.8;

import "forge-std/Test.sol";
import "../Raffle.sol";
import "./mocks/MockVRFCoordinatorV2.sol";

contract RaffleTest is Test {
    MockVRFCoordinatorV2 public vrfCoordinator;
    
    Raffle public raffle;
    address payable owner;
    address payable player1;
    address payable player2;
    address payable player3;

    uint96 constant BASE_FEE = 0.1 ether;
    uint256 constant INTERVAL = 30;
    uint256 constant ENTRANCE_FEE = 0.1 ether;
    bytes32 constant GAS_LANE = 0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc;
    uint32 constant CALLBACK_GAS_LIMIT = 500000;
    uint256 public staticTime;
    uint256 public currentBlock;

    uint96 constant FUND_AMOUNT = 1 * 10**18;

    event RaffleEnter(address indexed player);
    event RequestedRaffleWinner(uint256 indexed requestId);

    function setUp() public {
        staticTime = block.timestamp;
        currentBlock = block.number;
        player1 = payable(address(0x1));
        player2 = payable(address(0x2));
        player3 = payable(address(0x3));

        vrfCoordinator = new MockVRFCoordinatorV2();
        uint64 subId = vrfCoordinator.createSubscription();
        vrfCoordinator.fundSubscription(subId, FUND_AMOUNT);
        raffle = new Raffle(address(vrfCoordinator), ENTRANCE_FEE, GAS_LANE, subId, CALLBACK_GAS_LIMIT, INTERVAL);
        vm.warp(staticTime);
    }

    function testConstructor() public {
        uint256 entranceFee = raffle.getEntranceFee();
        assertEq(entranceFee, ENTRANCE_FEE);

        uint256 raffleState = raffle.getRaffleState();
        assertEq(raffleState, 0);

        uint256 interval = raffle.getInterval();
        assertEq(interval, INTERVAL);
    }

    function testNotEnoughEthToEnterRaffle() public {
        vm.expectRevert(Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle();
    }

    function testAddedToPlayersArray() public {
        vm.expectEmit(true, false, false, false);
        emit RaffleEnter(player1);
        startHoax(player1);
        raffle.enterRaffle{ value: ENTRANCE_FEE }();

        address firstPlayer = raffle.getPlayer(0);

        assertEq(firstPlayer, player1);
    }

    function testRecordsPlayerWhenTheyEnter() public {
        hoax(player1);
        raffle.enterRaffle{ value: ENTRANCE_FEE }();

        address playerEntered = raffle.getPlayer(0);
        assertEq(playerEntered, player1);
    }

    function testCantEnterWhenRaffleIsCalculating() public {
        hoax(player1);
        raffle.enterRaffle{ value: ENTRANCE_FEE }();

        hoax(player2);
        raffle.enterRaffle{ value: ENTRANCE_FEE }();

        vm.warp(staticTime + INTERVAL + 1);
        vm.roll(2);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("0x");
        assertTrue(upkeepNeeded);

        raffle.performUpkeep("");

        vm.expectRevert(Raffle__NotOpen.selector);
        hoax(player3);
        raffle.enterRaffle{ value: ENTRANCE_FEE }();
    }

    function testUpkeepReturnsFalseIfNoEthHasBeenSent() public {
        vm.warp(staticTime + INTERVAL + 1);
        vm.roll(2);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("0x");
        assertTrue(!upkeepNeeded);
    }

    function testUpkeepReturnsFalseIfRaffleIsNotOpen() public {
        raffle.enterRaffle{ value: ENTRANCE_FEE }();

        vm.warp(staticTime + INTERVAL + 1);
        vm.roll(2);

        raffle.performUpkeep("");

        uint256 raffleState = raffle.getRaffleState();
        (bool upkeepNeeded, ) = raffle.checkUpkeep("0x");
        assertEq(raffleState, 1);
        assertTrue(!upkeepNeeded);
    }

    function testUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        raffle.enterRaffle{ value: ENTRANCE_FEE }();

        vm.warp(staticTime + INTERVAL - 1);
        vm.roll(2);

        // TODO: Figure out how to revert with calldata included in error message,
        // had to change contract to make this work
        vm.expectRevert(Raffle__UpkeepNotNeeded.selector);
        raffle.performUpkeep("");

        (bool upkeepNeeded, ) = raffle.checkUpkeep("0x");
        assertTrue(!upkeepNeeded);
    }

    function testUpkeepReturnsTrueIfCriteriaIsMet() public {
        raffle.enterRaffle{ value: ENTRANCE_FEE }();

        vm.warp(staticTime + INTERVAL + 1);
        vm.roll(2);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("0x");
        assertTrue(upkeepNeeded);
    }

    function testPerformUpkeepCanRunIfUpkeepIsNeeded() public {
        raffle.enterRaffle{ value: ENTRANCE_FEE }();

        vm.warp(staticTime + INTERVAL + 1);
        vm.roll(2);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("0x");
        assertTrue(upkeepNeeded);

        raffle.performUpkeep("0x");
    }

    //NOTE: also emits a requestId, idk how to access it though because performUpkeep doesnt return anything
    function testPerformUpkeepUpdatesRaffleState() public {
        raffle.enterRaffle{ value: ENTRANCE_FEE }();

        vm.warp(staticTime + INTERVAL + 1);
        vm.roll(2);

        uint256 startingRaffleState = raffle.getRaffleState();
        assertEq(startingRaffleState, 0);

        raffle.performUpkeep("0x");

        uint256 endingRaffleState = raffle.getRaffleState();
        assertEq(endingRaffleState, 1);
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep() public {
        raffle.enterRaffle{ value: ENTRANCE_FEE }();

        vm.warp(staticTime + INTERVAL + 1);
        vm.roll(2);

        vm.expectRevert(bytes("nonexistent request"));
        vrfCoordinator.fulfillRandomWords(0, address(raffle));

        vm.expectRevert(bytes("nonexistent request"));
        vrfCoordinator.fulfillRandomWords(1, address(raffle));
    }

    //TODO: Full test with verified winner... The randomness makes this tricky lol
}