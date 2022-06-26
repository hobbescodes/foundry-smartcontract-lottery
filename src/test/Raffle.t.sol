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


        // TODO: Figure out how to act as Keeper.. 
        //right now it just always reverts with InvalidConsumer() on the requestRandomWords()
        raffle.performUpkeep("0x");

        vm.expectRevert(Raffle__NotOpen.selector);
        hoax(player3);
        raffle.enterRaffle{ value: ENTRANCE_FEE }();
    }
}