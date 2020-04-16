class MissionMultiplayerInv extends Inventory
	config(UT2004RPG);


//Baseline variables to simply check for the RPG mutator, Rules, and InteractionOwner that handles the HUD
var Controller InstigatorController;
var Pawn PawnOwner;
var MutUT2004RPG RPGMut;
var RPGRules Rules;
var transient DruidsRPGKeysInteraction InteractionOwner;

//Mission variables
var bool stopped;	//signifies whether a mission is paused or active.
var int MissionCount;		//The mission's current progress. This is updated by various events, such as making kills or standing in a specific location
var int MissionGoal;	//The mission's goal
var int MissionXP;		//The amount of experience rewarded to players after completing a mission
var localized string MissionName;
var config float CheckInterval;
var Pawn MMPIOwner;		//Pawn controlling the team mission for everyone
var bool MasterMMPI;	//True if this inventory controls the team mission for everyone
var int MissionClock;		//internal system for tracking time. Used in conjunction with TimeLimit.
var int TimeRemaining;
var config int Countdown;		//the time for players to prepare before the mission/minigame actually starts.
var int TimeLimit;	//time that mission or minigame must be completed by. Used in conjunction with MissionClock.
var config int ExpForWinAdd;	//How much end-game XP should increase by for completing missions
var bool RewardGranted;	//A condition to check if the XP reward has already been granted for completing the mission

//Boolean values for which mission is currently active
//Only one mission should be active at any given time
var bool PowerPartyActive;
var bool TarydiumKeepActive;
var bool BalloonPopActive;
var bool RingAndHoldActive;
var bool GenomeProjectActive;
var bool MusicalWeaponsActive;
var bool CoinGrabActive;
var bool PortalBallActive;

//Tarydium Keep Variables
var TarydiumCrystal TC;
var int TCHealth;

//Ring and Hold Variables
var RingRed RR;
var RingBlue RB;
var RingGold RG;
var bool RRActive, RBActive, RGActive;

//Genome Project Variables
var GenomeProjectNode GPN;
var config int GenomeXPPerVial;

//Musical Weapons Variables
var config Array < class <Weapon> > MusicalWeaponsList;	//The list of available weapons allowed for the Musical Weapons mission
var class<Weapon> ActiveWeapon;	//The current, active weapon that players must use for Musical Weapons
var config float MusicalChangeChance;	// % chance per CheckInterval the required weapon changes
var config int MusicalMinimumTime;	//how long in seconds a weapon should remain once changed. Prevents constant switching
var int MusicalCounter;	//A counter to be used with MusicalMinimumTime

//Coin Grab Variables
var config int CoinGrabXPPerCoin;

//Import audio files
#exec  AUDIO IMPORT NAME="MP3VoiceDraw" FILE="C:\UT2004\Sounds\MP3VoiceDraw.WAV" GROUP="MissionSounds"
#exec  AUDIO IMPORT NAME="MP3VoiceFinish" FILE="C:\UT2004\Sounds\MP3VoiceFinish.WAV" GROUP="MissionSounds"
#exec  AUDIO IMPORT NAME="MP3VoiceStart" FILE="C:\UT2004\Sounds\MP3VoiceStart.WAV" GROUP="MissionSounds"
#exec  AUDIO IMPORT NAME="MP3VoiceTimeUp" FILE="C:\UT2004\Sounds\MP3VoiceTimeUp.WAV" GROUP="MissionSounds"

replication
{
	reliable if (bNetInitial && Role == ROLE_Authority)
		PawnOwner;
	reliable if (Role == ROLE_Authority)
		Stopped, MissionName, MMPIOwner, MasterMMPI, MissionCount, MissionGoal, MissionXP, MissionClock, TimeRemaining, Countdown, TimeLimit, RewardGranted, PowerPartyActive, TarydiumKeepActive, TC, TCHealth, BalloonPopActive, RingAndHoldActive, RRActive, RBActive, RGActive, GenomeProjectActive, MusicalWeaponsActive, CoinGrabActive, PortalBallActive, ActiveWeapon;
}

simulated function PostBeginPlay()
{
	local Mutator M;

	Super.PostBeginPlay();

	if (Instigator != None)
		InstigatorController = Instigator.Controller;

	if (Level.Game != None)
		for (m = Level.Game.BaseMutator; m != None; m = m.NextMutator)
			if (MutUT2004RPG(m) != None)
			{
				RPGMut = MutUT2004RPG(m);
				break;
			}
	disable('Tick');
	CheckRPGRules();
}

function CheckRPGRules()
{
	Local GameRules G;

	if (Level.Game == None)
		return;		//try again later

	for(G = Level.Game.GameRulesModifiers; G != None; G = G.NextGameRules)
	{
		if(G.isA('RPGRules'))
		{
			Rules = RPGRules(G);
			break;
		}
	}

	if(Rules == None)
		Log("WARNING: Unable to find RPGRules in GameRules. EXP will not be properly awarded");
}

//GiveTo() initializes variables upon a new game or when a player joins the game
function GiveTo(Pawn Other, optional Pickup Pickup)
{
	if(Other == None)
	{
		destroy();
		return;
	}
	if (Invasion(Level.Game) == None)
	{
		Destroy();
		return;
	}
	if (InstigatorController == None)
		InstigatorController = Other.Controller;

	PawnOwner = Other;
	stopped = true;
	SetTimer(0, False);
	MMPIOwner = None;
	MasterMMPI = False;
	MissionCount = 0;
	MissionGoal = 0;
	MissionXP = 0;
	MissionClock = 0;
	TimeRemaining = 0;
	Countdown = default.Countdown;
	RewardGranted = False;
	PowerPartyActive = False;
	TarydiumKeepActive = False;
	BalloonPopActive = False;
	RingAndHoldActive = False;
	GenomeProjectActive = False;
	MusicalWeaponsActive = False;
	CoinGrabActive = False;
	PortalBallActive = False;
	ActiveWeapon = None;
	MusicalCounter = 0;
	
	Super.GiveTo(Other);
}

//The only person with a timer running is the team mission handler, set by the team mission artifact.
//The handler will loop through all controllers on the team and update everyone's mission variables
simulated function Timer()
{
	local Controller C;
	
	if(!stopped)
	{
		if (PawnOwner == None || PawnOwner.Health <= 0)	//Safety-check to make sure this gets destroyed
		{
			StopMission();
			Destroy();
		}
		else if (PawnOwner != None && PawnOwner.Health > 0)
		{
			Countdown--;	//start the countdown to commence mission/minigame. This gives players time to prepare and read the objective.
			if (Countdown == 0)
			{
				//Mission has started. Play a sound and read a message to all players
				for ( C = Level.ControllerList; C != None; C = C.NextController )
					if (C != None && C.Pawn != None && C.Pawn.Health > 0 && C.IsA('PlayerController') && C.SameTeamAs(PawnOwner.Controller) )
						PlayerController(C).ClientPlaySound(Sound'DEKRPG208C.MissionSounds.MP3VoiceStart');
				Level.Game.Broadcast(self, "Start!");
			}
			else if (Countdown > 0)	//still counting down to start minigame/mission.
			{
				//While in countdown, don't let anyone complete objectives or let objectives get destroyed
				if (MissionCount > 0)
					MissionCount = 0;
				if (TC != None)
				{
					TC.Health = TC.default.HealthMax;
					TCHealth = TC.default.HealthMax;
				}
			}
			else if (MissionClock >= TimeLimit && MissionClock != 0)		//When the time limit to complete the mission has been reached
			{
				//Play the "Time Up!" sound to all players
				for ( C = Level.ControllerList; C != None; C = C.NextController )
					if (C != None && C.Pawn != None && C.Pawn.Health > 0 && C.IsA('PlayerController') && C.SameTeamAs(PawnOwner.Controller) )
						PlayerController(C).ClientPlaySound(Sound'DEKRPG208C.MissionSounds.MP3VoiceTimeUp');
						
				//Certain missions do not have a mission goal, and we don't want to penalize players for not reaching a goal that hasn't been set
				//StopMission() will end the mission in a Mission Failed state for those missions that indeed have a goal
				if (GenomeProjectActive)
				{
					if (MissionCount > 0)
						MissionComplete();
					else
						StopMission();
				}
				else if (CoinGrabActive)
				{
					if (MissionCount > 0)
						MissionComplete();
					else
						StopMission();
				}
				else
					StopMission();
			}
			else
			{
				//Mission has started. Start the time limit and allow mission counts to accrue.
				
				MissionClock++;
				TimeRemaining = (TimeLimit - MissionClock);
			}
			
			//Throughout the duration of the mission, certain missions need special care when certain objectives are triggered
			
			//If the Tarydium crystals are destroyed, stop the mission
			if (TarydiumKeepActive)
			{
				if (TC != None)
					TCHealth = TC.Health;
				if (TC == None || TC.Health <= 0)
				{
					StopMission();
				}
			}
			
			//If any Red, Blue, or Gold rings are not held, reset the mission counter
			if (RingAndHoldActive)
			{
				if (RR != None)
				{
					if (RR.CheckRadius())
						RRActive = True;
					else
						RRActive = False;
				}
				if (RB != None)
				{
					if (RB.CheckRadius())
						RBActive = True;
					else
						RBActive = False;
				}
				if (RG != None)
				{
					if (RG.CheckRadius())
						RGActive = True;
					else
						RGActive = False;
				}
			}
			
			//Constantly randomize the weapons in Musical Weapons
			if (MusicalWeaponsActive)
			{
				MusicalCounter++;	//Increment the counter each second
				if (MusicalCounter >= MusicalMinimumTime)	//Once the counter reaches the minimum time, then we can swap a new weapon. This prevents constant weapon switching
				{
					if ( Rand(100) <= MusicalChangeChance)
					{
						ActiveWeapon = MusicalWeaponsList[Rand(MusicalWeaponsList.Length)];	//Randomly select a weapon from the list
						MusicalCounter = 0;
					}
				}
			}
			
			//Call Replicate() to update everyone's mission inventory with the handler's mission inventory
			Replicate();
			
			//Now let's check to see if MissionCount has reached MissionGoal
			//If so, stop the timer and reward players.
			if ( MasterMMPI && MissionCount != 0 && MissionGoal != 0 && MissionCount >= MissionGoal)
			{
				if (!RewardGranted)		//This condition is checked to ensure that the Mission Handler does not repeatedly call MissionComlete while ghosting
					MissionComplete();
				else	//Player must be ghosting and this function is getting repeatedly called
					StopMission();
			}
		}
	}
	else
		return;
}

//Replicate() synchronizes everyone's mission inventory with the handler's mission inventory
//We loop through all controllers in the game and set their mission's variables to the handler's variables

simulated function Replicate()
{
	local Controller C, NextC;
	local Pawn P;
	local MissionMultiplayerInv MMPI;
	
	C = Level.ControllerList;
	while (C != None)
	{
		NextC = C.NextController;
		if(C == None)
		{
			C = NextC;
			break;
		}
		if (C != None && C.Pawn != None && C.Pawn.Health > 0 && C.Pawn != MMPIOwner)
		{
			P = C.Pawn;
			if(P != None && P.isA('Vehicle'))
				P = Vehicle(P).Driver;
			if (P != None && P != PawnOwner && (P.GetTeam() == PawnOwner.GetTeam() && PawnOwner.GetTeam() != None) )
				MMPI = MissionMultiplayerInv(P.FindInventoryType(class'MissionMultiplayerInv'));
			if (MMPI != None)
			{
				MMPI.MMPIOwner = MMPIOwner;
				MMPI.MasterMMPI = False;
				MMPI.MissionName = MissionName;
				MMPI.TimeLimit = TimeLimit;
				MMPI.MissionCount = MissionCount;
				MMPI.TimeRemaining = TimeRemaining;
				MMPI.MissionGoal = MissionGoal;
				if (Countdown <= 0)
					MMPI.stopped = False;
				if (PowerPartyActive)
					MMPI.PowerPartyActive = True;
				if (TarydiumKeepActive)
				{
					MMPI.TarydiumKeepActive = True;
					MMPI.TC = TC;
				}
				if (BalloonPopActive)
					MMPI.BalloonPopActive = True;
				if (RingAndHoldActive)
				{
					MMPI.RingAndHoldActive = True;
					if (RRActive)
						MMPI.RRActive = True;
					else
						MMPI.RRActive = False;
					if (RBActive)
						MMPI.RBActive = True;
					else
						MMPI.RBActive = False;
					if (RGActive)
						MMPI.RGActive = True;
					else
						MMPI.RGActive = False;
				}
				if (GenomeProjectActive)
					MMPI.GenomeProjectActive = True;
				if (MusicalWeaponsActive)
				{
					MMPI.MusicalWeaponsActive = True;
					MMPI.ActiveWeapon = ActiveWeapon;
				}
				if (CoinGrabActive)
					MMPI.CoinGrabActive = True;
				if (PortalBallActive)
					MMPI.PortalBallActive = True;
			}
		}
		C = NextC;
	}
}

//UpdateCounts() is called by various events- a player making a kill, using a certain weapon, etc.
//UpdateCounts() will increment the mission handler's MissionCount as objectives are achieved
//In turn, Timer() will loop through all controllers and update everyone else's MissionCount

static function UpdateCounts(int Count)
{
	local MissionMultiplayerInv MMPI;
	local Pawn P;
	local Vehicle V;
	
	P = default.MMPIOwner;
	
	if (P.DrivenVehicle != None)
		V = Vehicle(P);
	
	if (P != None && V != None)
		P = V.Driver;	
	
	if (P != None && P.Health > 0)
	{
		MMPI = MissionMultiplayerInv(P.FindInventoryType(class'MissionMultiplayerInv'));
		if ( MMPI != None && !MMPI.Stopped && MMPI.MasterMMPI)
			MMPI.MissionCount += Count;
	}
}

//StopMission() stops the current mission by looping through all controllers and calling StopEffect()
simulated function StopMission()
{
	local Controller C, NextC;
	local Pawn P;
	local MissionMultiplayerInv MMPI;
	
	//Display a Mission Failed message. Womp Womp
	if (!RewardGranted)
	{
		if (TarydiumKeepActive)
			Level.Game.Broadcast(self, "Tarydium destroyed! Team mission failed.");
		else
			Level.Game.Broadcast(self, "Team mission failed.");
	}
	
	C = Level.ControllerList;
	while (C != None)
	{
		NextC = C.NextController;
	
		if(C == None)
		{
			C = NextC;
			break;
		}
		
		if (C != None && C.Pawn != None && C.Pawn.Health > 0)
		{
			P = C.Pawn;
			if(P != None && P.isA('Vehicle'))
				P = Vehicle(P).Driver;
			if (P != None && (P.GetTeam() == PawnOwner.GetTeam() && PawnOwner.GetTeam() != None) )
				MMPI = MissionMultiplayerInv(P.FindInventoryType(class'MissionMultiplayerInv'));
			if (MMPI != None)
			{
				MMPI.StopEffect();
			}
		}
		C = NextC;
	}
}

//MissionComplete() is called when a mission goal has been reached
//MissionComplete() rewards XP to everyone on the team and increases the end-game XP
//Also handles the destruction of any mission-related objectives
simulated function MissionComplete()
{
	local Controller C, NextC;
	local Pawn P;
	local MissionMultiplayerInv MMPI;
	
	//An important boolean to set here so that MissionComplete() does not get called repeatedly for a mission handler who is ghosting
	RewardGranted = True;
	
	//Add end-game XP
	if (RPGMut != None)
	{
		RPGMut.EXPForWin += default.EXPForWinAdd;
	}
	
	//Broadcast a Mission Completed message to everyone
	if (GenomeProjectActive)
	{
		Level.Game.Broadcast(self, "" $ MissionName $ ": +" $ (MissionCount*GenomeXPPerVial) $ " XP.");
	}
	else if (CoinGrabActive)
	{
		Level.Game.Broadcast(self, "" $ MissionName $ ": +" $ (MissionCount*CoinGrabXPPerCoin) $ " XP.");
	}
	else
	{
		Level.Game.Broadcast(self, "" $ MissionName $ " complete! +" $ MissionXP $ " XP.");
	}
		Level.Game.Broadcast(self, "+" $ ExpForWinAdd $ " end of game XP.");
	
	//Loop through all controllers and reward XP
	//Certain missions will have their own way of rewarding XP rather than using a flat amount
	C = Level.ControllerList;
	while (C != None)
	{
		NextC = C.NextController;

		if(C == None)
		{
			C = NextC;
			break;
		}
		
		if (C != None && C.Pawn != None && C.Pawn.Health > 0)
		{
			P = C.Pawn;
			if(P != None && P.isA('Vehicle'))
				P = Vehicle(P).Driver;
			if (P != None && (P.GetTeam() == PawnOwner.GetTeam() && PawnOwner.GetTeam() != None) )
				MMPI = MissionMultiplayerInv(P.FindInventoryType(class'MissionMultiplayerInv'));
			if (MMPI != None)
			{
				if ((MissionXP > 0) && (Rules != None))
				{
					if (GenomeProjectActive)
					Rules.ShareExperience(RPGStatsInv(C.Pawn.FindInventoryType(class'RPGStatsInv')), (MissionCount*GenomeXPPerVial));
					else if (CoinGrabActive)
					Rules.ShareExperience(RPGStatsInv(C.Pawn.FindInventoryType(class'RPGStatsInv')), (MissionCount*CoinGrabXPPerCoin));
					else
						Rules.ShareExperience(RPGStatsInv(P.FindInventoryType(class'RPGStatsInv')), MissionXP);
				}
				
				//Call StopEffect() and stop the timer on everyone's mission inventory
				
				MMPI.StopEffect();
				MMPI.SetTimer(0, False);
				
				//Only play the "Finished!" sound for missions with end goals
				if (!GenomeProjectActive && !CoinGrabActive)
				{
					if (PlayerController(C) != None)
						PlayerController(C).ClientPlaySound(Sound'DEKRPG208C.MissionSounds.MP3VoiceFinish');
				}
			}
		}
		C = NextC;
	}
	if (TC != None)
		TC.Destroy();
	if (RR != None)
		RR.Destroy();
	if (RB != None)
		RB.Destroy();
	if (RG != None)
		RG.Destroy();
	if (GPN != None)
		GPN.Destroy();
}

//StopEffect() stops the timer by setting the check interval to 0 and the loop to false
//All mission variables are re-initialized to their starting values so a new mission can start
//As a safety-measure, all mission objectives are destroyed here as well
function stopEffect()
{
	local Pawn P;
	
	P = PawnOwner;
	if(P != None && P.isA('Vehicle'))
		P = Vehicle(P).Driver;
	if (P != None)
	{
		stopped = true;
		SetTimer(0, False);
		MMPIOwner = None;
		MasterMMPI = False;
		MissionCount = 0;
		MissionGoal = 0;
		MissionXP = 0;
		MissionClock = 0;
		TimeRemaining = 0;
		Countdown = default.Countdown;
		RewardGranted = False;
		PowerPartyActive = False;
		TarydiumKeepActive = False;
		BalloonPopActive = False;
		RingAndHoldActive = False;
		GenomeProjectActive = False;
		MusicalWeaponsActive = False;
		CoinGrabActive = False;
		PortalBallActive = False;
		ActiveWeapon = None;
		if (TC != None)
			TC.Destroy();
		if (RR != None)
			RR.Destroy();
		if (RB != None)
			RB.Destroy();
		if (RG != None)
			RG.Destroy();
		if (GPN != None)
			GPN.Destroy();
	}
}

//Destroyed is only called when a player dies(all Inventories are destroyed on the Pawn) or when the player leaves the game
//We want to do a baton pass here and select a new player to handle team missions before the Mission Handler's inventory gets destroyed
simulated function Destroyed()
{
	local Controller C, NextC;
	local Pawn P;
	local MissionMultiplayerInv MMPI;
	
	//Important HUD-related elements that need to be destroyed
 	if( InteractionOwner != None )
 	{
 		InteractionOwner.MMPI = None;
 		InteractionOwner = None;
 	}
	
	//If the Handler, pass off the Mission to someone else before destroying
	if (MasterMMPI && !stopped)
	{
		C = Level.ControllerList;
		while (C != None)
		{
			NextC = C.NextController;
	
			if(C == None)
			{
				C = NextC;
				break;
			}
		
			if (C != None && C.Pawn != None && C.Pawn.Health > 0)
			{
				P = C.Pawn;
				if(P != None && P.isA('Vehicle'))
					P = Vehicle(P).Driver;
				if (P != None && (P.GetTeam() == PawnOwner.GetTeam() && PawnOwner.GetTeam() != None) )
					MMPI = MissionMultiplayerInv(P.FindInventoryType(class'MissionMultiplayerInv'));
					
				//Only a few things need to get passed- MasterMMPI, MMPIOwner, and setting the timer on the new Handler's inventory
				//The new Handler will call Replicate() in Timer and will  update everyone else's missions
				if (MMPI != None)
				{
					MMPI.MasterMMPI = True;
					MMPI.MMPIOwner = C.Pawn;
					MMPI.SetTimer(MMPI.CheckInterval, True);
					
					break;	//We've found a replacement. Get out of the loop here
				}
			}
			C = NextC;
		}
	}
	Super.Destroyed();
}

defaultproperties
{
	MusicalChangeChance=10
	MusicalMinimumTime=5
	MusicalWeaponsList(0)=class'DEKWeapons208C.INAVRiL'
	MusicalWeaponsList(1)=class'XWeapons.BioRifle'
	MusicalWeaponsList(2)=class'XWeapons.ShockRifle'
	MusicalWeaponsList(3)=class'UT2004RPG.RPGLinkGun'
	MusicalWeaponsList(4)=class'XWeapons.Minigun'
	MusicalWeaponsList(5)=class'XWeapons.FlakCannon'
	MusicalWeaponsList(6)=class'XWeapons.RocketLauncher'
	MusicalWeaponsList(7)=class'XWeapons.SniperRifle'
	CheckInterval=1.000000
	Countdown=10
	ExpForWinAdd=10
	GenomeXPPerVial=5
	MessageClass=Class'UnrealGame.StringMessagePlus'
}
