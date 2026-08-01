# Dying Light 2 — usable RTTI types (engine / gamedll)

> **Raw dump.** Prefer curated names in [function-catalog.md](function-catalog.md) and topic docs.  
> Status: **raw extract** — [INDEX.md](INDEX.md). Not a live instance map.

**Source:** offline MSVC RTTI (`.?AV` / `.?AU` strings) in:
- `/mnt/r/engine_x64_rwdi.dll`
- `/mnt/r/gamedll_ph_x64_rwdi.dll`

**No game process required** for this dump. Live attach still needed to resolve instances / call APIs.

**Filter:** player, level, inventory, health, time/weather, entity roots; template/GUI/lambda noise removed.

**Related:** [function-catalog.md](function-catalog.md), [player-variables.md](player-variables.md), [modules.md](modules.md).

**Date:** 2026-08-01

## How to use this file

1. **Search** (`rg`, editor find) for a type fragment (`InventoryMoney`, `LifeHealth`, `TimeWeather`, `PlayerVariables`).  
2. Prefer **gamedll** names for gameplay objects; **engine** for systems like TimeWeather / ILevel / IGame.  
3. **Priority** section below is the high-signal subset for cheats — start there.  
4. Full lists further down are bulk; do not treat every name as present or useful on the current build.  
5. After finding a name, switch to topic docs for **offsets and chains** (this file has almost none).

## Priority (cheat / bootstrap relevant)

### engine_x64_rwdi

- `CEntity`
- `IGame`
- `IGameForGuiInterface`
- `ILevel`
- `Matchmaking::IGamesList`
- `Net::Repl::IGame`
- `Net::Repl::IGameObject`
- `Net::Repl::ILevelInfo`
- `Net::Repl::VIGameObject`
- `Network::IGameAddress`
- `TimeWeather::CAsyncLoadTexture`
- `TimeWeather::CAsyncStreamTexture`
- `TimeWeather::CAudioSubsystem`
- `TimeWeather::CGpuFxSubsystem`
- `TimeWeather::CTimeWeatherMutator`
- `TimeWeather::CVarlistSubsystem`
- `TimeWeather::IResource`
- `TimeWeather::ISubsystem`
- `cbs::CEntity`
- `cbs::VCEntity`

### gamedll_ph_x64_rwdi

- `AEBVPlayerState`
- `BoolPlayerVariable`
- `CEntity`
- `CoAIObservablePlayerDI`
- `CustomMoveObjectDef::IGameActionParser`
- `ESurvivorMissionPlayerState::W4TYPE`
- `FloatPlayerVariable`
- `GameState::IGameState`
- `GameState::IGameState::FindMostRecent`
- `GameState::IGameState::IPredicate`
- `GameState::IGameState::IRemoteStates`
- `IGame`
- `IGameAudioEventRequester`
- `IGameForGuiInterface`
- `IGameObject`
- `ILevel`
- `ILevelLauncher`
- `IPlayerManager`
- `InventoryMoney`
- `Matchmaking::AEBVIGamesList`
- `Matchmaking::IGamerCard`
- `Matchmaking::IGamesList`
- `PlayerDI`
- `PlayerDI_PH`
- `PlayerHealthModule`
- `PlayerState`
- `PlayerStateBackup::Element`
- `PlayerStateBackup::LevelElement`
- `PlayerStateBackup::PlayerElement`
- `PlayerVariable`
- `Savegame::DayTimeWeather::State`
- `Savegame::DayTimeWeather::VState`
- `Savegame::ExamplePlayerStateElement`
- `Savegame::ExamplePlayerStateElement_v02`
- `Savegame::PlayerStateElement`
- `Savegame::Session::W4EStorePlayerState`
- `Savegame::VExamplePlayerStateElement`
- `Savegame::VExamplePlayerStateElement_v02`
- `Savegame::VPlayerStateElement`
- `SessionRestart::TeleportPlayerState`
- `StringPlayerVariable`
- `SurvivorMissionPlayerStateChangedEvent`
- `SyncActions::SyncActionConditionPlayerVariableBool`
- `TimeWeather::ISubsystem`
- `VBoolPlayerVariable`
- `VCoAIObservablePlayerDI`
- `VFloatPlayerVariable`
- `VPlayerDI`
- `VPlayerDI_PH`
- `VPlayerHealthModule`
- `VPlayerState`
- `VPlayerVariables`
- `VPlayerVariables::FieldMeta`
- `VStringPlayerVariable`
- `VSurvivorMissionPlayerStateChangedEvent`
- `cbs::CEntity`
- `cbs::VCEntity`
- `cbs::XAEAVCEntity`
- `lifecs::ILifeHealth`
- `lifecs::VILifeHealth`

## engine_x64_rwdi — filtered list (28)

```
CEntity
IGame
IGameForGuiInterface
ILevel
Matchmaking::IGamesList
Net::0Services::Eos::Inventory
Net::0Services::Inventory
Net::0Services::Local::Inventory
Net::0Services::Null::Inventory
Net::0Services::Steam::Inventory
Net::0Services::Tos::Inventory
Net::Repl::IGame
Net::Repl::IGameObject
Net::Repl::ILevelInfo
Net::Repl::VIGameObject
Net::Services::Inventory::IInventory
Network::IGameAddress
TimeWeather::CAsyncLoadTexture
TimeWeather::CAsyncStreamTexture
TimeWeather::CAudioSubsystem
TimeWeather::CGpuFxSubsystem
TimeWeather::CTimeWeatherMutator
TimeWeather::CVarlistSubsystem
TimeWeather::IResource
TimeWeather::ISubsystem
bp::W4EWeaponType
cbs::CEntity
cbs::VCEntity
```

## gamedll_ph_x64_rwdi — filtered list (425)

```
AEBVPlayerState
AIInventoryManager
ActivityModuleWeaponAim
ActivityModuleWeaponAim::W4EType
ActivityModuleWeaponAim::WeaponAimGraphInterface
ActivityModuleWeaponReload
ActivityModuleWeaponReload::WeaponReloadGraphInterface
ActivityModuleWeaponShoot
ActivityModuleWeaponShoot::W4EType
ActivityModuleWeaponShoot::WeaponShootGraphInterface
ActivityModuleWeaponSwitch
ActivityModuleWeaponSwitch::WeaponSwitchGraphInterface
BT::Act_AttackIfInWeaponRange
BT::Act_ChangeWeapon
BT::Act_WeaponAim
BT::Act_WeaponReload
BT::Act_WeaponShoot
BT::Cnd_ActiveWeaponDamageType
BT::Cnd_HasActiveWeapon
BT::Cnd_HasActiveWeaponSpecific
BT::Cnd_HasTargetLowStamina
BT::Cnd_HasThrowableInInventory
BT::Cnd_HasThrowableKnifeInInventory
BT::Cnd_HasThrowableMolotovInInventory
BT::Cnd_HasWeaponInInventory
BT::Cnd_HasWeaponInInventorySpecific
BT::Cnd_InStaminaRecovery
BT::Cnd_IsAnyPlayerDialogPlaying
BT::Cnd_IsPrimaryWeaponReloaded
BT::Cnd_IsSwitchingWeapon
BT::Cnd_IsTargetUsingWeapon
BT::Cnd_IsWeaponAimSteady
BT::Cnd_IsWeaponThrowTrajectoryValid
BT::Cnd_ScenarioAIHasWeaponInInventory
BT::Cnd_ShouldDodgeCombatTargetThrowWeaponAttack
BT::Cnd_ShouldHaveWeaponReady
BT::Cnd_StaminaDepleted
BT::Opr_BehaviorPlaceGetRequiredWeaponType
BT::Opr_CreateHumanWeaponModule
BT::Opr_DealStaminaDamage
BT::Opr_GetLocalPlayer
BT::Opr_GetPlayerDir
BT::Opr_SetWeapon
BT::Opr_SetWeaponSpecific
BT::Opr_TryDecreaseStamina
BarkSystem::BarkQueryContext::W4EQuerierBarkWeaponType
BarkSystem::LocalPlayerHealthCondtion
BarkSystem::PlayerEquippedWeaponMinColorCondition
BaseWeaponModule
BoolPlayerVariable
CEntity
CGuiGameDataRoot
CGuiGameEngineDataRoot
CGuiLevelUpBigMessage
CGuiPlayerHealthValueChanged
CScriptConditionEquippedWeaponItemCategory
CScriptConditionEquippedWeaponItemType
CScriptConditionEquippedWeaponName
CScriptConditionInventoryItemCategory
CScriptConditionInventoryItemType
CScriptConditionPlayerHealth
CScriptConditionPlayerHealthCritical
CScriptConditionPlayerStamina
CScriptConditionPlayerStaminaDepleted
CWeaponShootEvent
CoAIObservablePlayerDI
CoDayNightSpawnModifier
CoGivePlayerStamina
CustomMoveObjectDef::IGameActionParser
DayNightController
DayNightCycle
DetectorWeaponVis
EGuiWeaponClass::W4TYPE
EGuiWeaponType::W4TYPE
EMinigameMode::W4TYPE
EMinigameResult::W4TYPE
ESurvivorMissionPlayerState::W4TYPE
EWeaponProperty::W4TYPE
EWeaponPropertyCS::W4TYPE
EWeaponShootMode::W4TYPE
Evn_CreateWeapon
FireWeaponVis
FloatPlayerVariable
GameState::IGameState
GameState::IGameState::FindMostRecent
GameState::IGameState::IPredicate
GameState::IGameState::IRemoteStates
GlideController
GuiGameplayHintWidget
GuiGameplayModifierData
GuiGameplayTabs
GuiGameplayTabsBtnActionEvent
GuiGameplayTabsBtnData
GuiGameplayTabsStoreBtnData
GuiInventoryBreadcrumb
GuiInventoryItemData
GuiInventoryOutfitData
GuiPlayerInventorySizeInfo
GuiPlayerInventorySizeInfo_CS
GuiProgressMinigameData
GuiQuickSelectPartWeapons
GuiQuickSelectWeapons
GuiStaminaBar
GuiTowerRaidInventoryItemData
GuiWeaponBrokneNotificationMessage
GuiWeaponSelectorBalatroCharmInfo
GuiWeaponSelectorItem
GuiWeaponSelectorModInfo
GuiWeaponSelectorWidget
HintConditionJunkWeapon
HintConditionLowStamina
HintConditionNoStamina
Hints::CndBetterWpnInInventoryThanQSlots
Hints::CndIsActivityStaminaFulfilled
Hints::CndIsInfiniteParkourStamina
Hints::CndLowStamina
Hints::ItemAddedToInventory
Hints::WeaponBadlyDamagedTrigger
HumanWeaponModule
HumanWeaponModule::WeaponGraphInterface
IEventWeaponFilter
IGame
IGameAudioEventRequester
IGameForGuiInterface
IGameObject
IGuiInventoryDataSource
IInventory
IInventoryItemController
IInventoryObserver
IInventoryOwner
IInventoryWallet
ILevel
ILevelLauncher
IMinigameController
IPlayerManager
IWeaponVisOwner
Inventory::ItemAddContext
Inventory::ItemAddHelper
Inventory::ItemAddResults
InventoryBaseForItems
InventoryCollectable
InventoryContainer
InventoryContainerDI
InventoryDebugFilteredRandomItemsCache
InventoryItem
InventoryItems
InventoryItemsAmmo
InventoryLooseItems
InventoryMain
InventoryMoney
InventoryNet
InventorySpecial
InventoryToken
ItemDescInventory
ItemDescStaminaBooster
ItemDescWeapon
ItemDescWeaponModification
MOTDMoviePlayerDialogController
Matchmaking::AEBVIGamesList
Matchmaking::IGamerCard
Matchmaking::IGamesList
MenuInventoryBaseController
MenuInventoryConsumableSelectionScreen
MenuInventoryController
MenuInventoryController_PH
MenuInventoryEquipmentSelectionScreen
MenuInventoryItemSelectionBaseController
MenuInventoryOutfitsSelectionScreen
MenuInventoryWeaponSelectionScreen
MenuModelManager::InventoryItemModelContext
MenuModifyWeaponCanDismantleEvent
MenuModifyWeaponCanModifyEvent
MenuModifyWeaponController
MenuModifyWeaponEvent
MenuModifyWeaponResetInspectModeMtxEvent
MenuModifyWeaponSetInspectModeEvent
MenuModifyWeaponShowContext
MenuWorkbenchSelectWeaponForModdingEvent
MessageDataHasWeaponInInventory
OnInventoryItemClearBreadcrumb
OnInventoryItemFillDismantleResults
OnInventoryItemFocused
PEAVGuiGameplayTabsBtnData
PEAVGuiInventoryItemData
PEAVInventoryItem
PlayerDI
PlayerDI_PH
PlayerDifficultyModule
PlayerHealthModule
PlayerInventoryModule
PlayerStaminaModule
PlayerState
PlayerStateBackup::Element
PlayerStateBackup::LevelElement
PlayerStateBackup::PlayerElement
PlayerVariable
QuestInventoryItemDI
RepairWeaponController
Savegame::DayTimeWeather::State
Savegame::DayTimeWeather::VState
Savegame::ExamplePlayerStateElement
Savegame::ExamplePlayerStateElement_v02
Savegame::Inventory::BaseItem
Savegame::Inventory::BaseItem::Mod
Savegame::Inventory::BaseItem::VMod
Savegame::Inventory::DlcStashSet
Savegame::Inventory::GrantedConsumable
Savegame::Inventory::Group
Savegame::Inventory::Item
Savegame::Inventory::ItemContainer
Savegame::Inventory::ItemId
Savegame::Inventory::ItemSpot
Savegame::Inventory::Loadout
Savegame::Inventory::LoadoutWeapon
Savegame::Inventory::OutfitPart
Savegame::Inventory::QuickSlot
Savegame::Inventory::QuickSlots
Savegame::Inventory::SlotItem
Savegame::Inventory::Snapshot
Savegame::Inventory::State
Savegame::Inventory::ToolSkin
Savegame::Inventory::VBaseItem
Savegame::Inventory::VDlcStashSet
Savegame::Inventory::VGrantedConsumable
Savegame::Inventory::VGroup
Savegame::Inventory::VItem
Savegame::Inventory::VItemContainer
Savegame::Inventory::VItemId
Savegame::Inventory::VItemSpot
Savegame::Inventory::VLoadout
Savegame::Inventory::VLoadoutWeapon
Savegame::Inventory::VOutfitPart
Savegame::Inventory::VQuickSlot
Savegame::Inventory::VQuickSlots
Savegame::Inventory::VSlotItem
Savegame::Inventory::VSnapshot
Savegame::Inventory::VState
Savegame::Inventory::VToolSkin
Savegame::PlayerStateElement
Savegame::Session::Inventory::Event
Savegame::Session::Inventory::ItemDefinionsEvent
Savegame::Session::Inventory::LoadedRttiDataChunkEvent
Savegame::Session::Inventory::LoadedStateEvent
Savegame::Session::Inventory::Monitor
Savegame::Session::Inventory::PlayerCreatedEvent
Savegame::Session::Inventory::PlayerDestroyedEvent
Savegame::Session::Inventory::RttiSerializationEvent
Savegame::Session::Inventory::SaveScanEvent
Savegame::Session::Inventory::SavedRttiDataChunkEvent
Savegame::Session::Inventory::SavedStateEvent
Savegame::Session::Inventory::StoredStateEvent
Savegame::Session::Inventory::UpdatedItemDefinitionsEvent
Savegame::Session::Inventory::ValidatedItemDefinitionsEvent
Savegame::Session::Inventory::W4EEvent
Savegame::Session::Inventory::W4EEventAnalysisResult
Savegame::Session::Inventory::W4EItemDefinionsEvent
Savegame::Session::Inventory::W4ERttiSerializationEvent
Savegame::Session::Inventory::W4ESaveScanEvent
Savegame::Session::Inventory::W4ETelemetrySendMode
Savegame::Session::SingleplayerState
Savegame::Session::W4EStorePlayerState
Savegame::VExamplePlayerStateElement
Savegame::VExamplePlayerStateElement_v02
Savegame::VPlayerStateElement
SessionRestart::TeleportPlayerState
StaminaBarPart
Story::ClearPlayerInventoryLogic
Story::GiveOpportunityWeaponLogic
Story::PlayerHealthWaitLogic
Story::PlayerHealthWaitLogic::W4EMode
Story::RemoveAllOpportunityWeaponsLogic
Story::Reward::InventoryItem
Story::Reward::VInventoryItem
Story::SetPlayerHealthLogic
Story::ShowPlayerInventoryNotificationLogic
Story::VClearPlayerInventoryLogic
Story::VGiveOpportunityWeaponLogic
Story::VPlayerHealthWaitLogic
Story::VRemoveAllOpportunityWeaponsLogic
Story::VSetPlayerHealthLogic
Story::VShowPlayerInventoryNotificationLogic
Story::Variable::Function_PlayerGetStaminaUpgradeCount
Story::Variable::PlayerControlCanUseWeaponNode
Story::Variable::PlayerControlInfiniteParkourStaminaNode
Story::Variable::PlayerControlInfiniteStaminaNode
Story::Variable::PlayerControlMaxStaminaNode
Story::Variable::PlayerHealthNode
Story::Variable::PlayerHealthPercentageNode
Story::Variable::PlayerStaminaNode
Story::Variable::VFunction_PlayerGetStaminaUpgradeCount
StringPlayerVariable
SurvivorMissionPlayerStateChangedEvent
SyncActions::ISyncActionHelper_Inventory
SyncActions::SyncActionConditionEquippedWeaponStatsTypeRequired
SyncActions::SyncActionConditionEquippedWeaponTypeRequired
SyncActions::SyncActionConditionInventoryItemRequired
SyncActions::SyncActionConditionInventoryItemTypeRequired
SyncActions::SyncActionConditionIsLocalPlayerNear
SyncActions::SyncActionConditionPlayerVariableBool
SyncActions::SyncActionConditionStaminaBelow
SyncActions::SyncActionEventActivateInventoryItem
SyncActions::SyncActionEventAddStamina
SyncActions::SyncActionEventDropInventoryItem
SyncActions::SyncActionEventFreezeStamina
SyncActions::SyncActionEventHideInventoryItem
SyncActions::SyncActionEventRemoveInventoryItem
SyncActions::SyncActionEventShowInventoryItem
SyncActions::SyncActionEventShowInventoryItemOfType
TimeWeather::ISubsystem
USEventSignal_WeaponCreated
UVWeaponVis
VActivityModuleWeaponAim
VActivityModuleWeaponReload
VActivityModuleWeaponShoot
VActivityModuleWeaponSwitch
VBaseWeaponModule
VBoolPlayerVariable
VCGuiGameDataRoot
VCGuiGameEngineDataRoot
VCGuiLevelUpBigMessage
VCGuiPlayerHealthValueChanged
VCWeaponShootEvent
VCoAIObservablePlayerDI
VCoDayNightSpawnModifier
VCoGivePlayerStamina
VDetectorWeaponVis
VFireWeaponVis
VFloatPlayerVariable
VGlideController
VGuiGameplayHintWidget
VGuiGameplayModifierData
VGuiGameplayTabs
VGuiGameplayTabsBtnActionEvent
VGuiGameplayTabsBtnData
VGuiGameplayTabsStoreBtnData
VGuiInventoryBreadcrumb
VGuiInventoryItemData
VGuiInventoryOutfitData
VGuiPlayerInventorySizeInfo
VGuiPlayerInventorySizeInfo_CS
VGuiProgressMinigameData
VGuiQuickSelectPartWeapons
VGuiQuickSelectWeapons
VGuiStaminaBar
VGuiTowerRaidInventoryItemData
VGuiWeaponBrokneNotificationMessage
VGuiWeaponSelectorBalatroCharmInfo
VGuiWeaponSelectorItem
VGuiWeaponSelectorModInfo
VGuiWeaponSelectorWidget
VHumanWeaponModule
VInventoryDebugFilteredRandomItemsCache
VMOTDMoviePlayerDialogController
VMenuInventoryBaseController
VMenuInventoryConsumableSelectionScreen
VMenuInventoryController
VMenuInventoryController_PH
VMenuInventoryEquipmentSelectionScreen
VMenuInventoryItemSelectionBaseController
VMenuInventoryOutfitsSelectionScreen
VMenuInventoryWeaponSelectionScreen
VMenuModifyWeaponCanDismantleEvent
VMenuModifyWeaponCanModifyEvent
VMenuModifyWeaponController
VMenuModifyWeaponEvent
VMenuModifyWeaponResetInspectModeMtxEvent
VMenuModifyWeaponSetInspectModeEvent
VMenuWorkbenchSelectWeaponForModdingEvent
VOnInventoryItemClearBreadcrumb
VOnInventoryItemFillDismantleResults
VOnInventoryItemFocused
VPlayerDI
VPlayerDI_PH
VPlayerDifficultyModule
VPlayerHealthModule
VPlayerInventoryModule
VPlayerStaminaModule
VPlayerState
VPlayerVariables
VPlayerVariables::FieldMeta
VQuestInventoryItemDI
VRepairWeaponController
VStaminaBarPart
VStringPlayerVariable
VSurvivorMissionPlayerStateChangedEvent
VUVWeaponVis
VWeaponBowController
VWeaponFireRightController
VWeaponFppShadowVis
VWeaponMeleeController
VWeaponThrowController
VWeaponVis
W4EGuiGameplayTabsBtnAction
W4EInventory
W4EInventoryGroup
W4EMenuModifyWeaponActions
W4EPlayerDifficultyTrigger
W4EStashEventInventoryType
W4EStashPHEventInventoryType
W4ESubInventory
W4EWeaponModeType
WeaponBowController
WeaponFireController
WeaponFireRightController
WeaponFppShadowVis
WeaponMeleeController
WeaponThrowController
WeaponVis
XPEAVGuiGameplayTabsBtnData
XPEAVGuiInventoryItemData
_NPEAVGuiInventoryItemData
activity::StaminaReq
ai::Stamina::UStaminaPreset
ai::Stamina::UStaminaPreset::FieldMeta
ai::Stamina::UStaminaPreset::M
ai::Stamina::W4EState
ai::W4EWeaponDamageType
ai::W4EWeaponHand
ai::W4EWeaponType
ai::W4EWeaponTypeSpecific
cbs::CEntity
cbs::VCEntity
cbs::XAEAVCEntity
lifecs::ILifeHealth
lifecs::VILifeHealth
```

## Live dump note

Dumping **all** RTTI from a running process is possible (scan module for `.?AV`) but duplicates this offline extract for MSVC builds. Prefer offline DLL dump after updates.

Live usefulness of RTTI is **`getRTTIClassName(object)`** on pointers you already have (e.g. confirm `PlayerState`, `PlayerDI_PH`, `StringPlayerVariable`).

**Same mechanism as CE UI:** Memory View → **Define New Structure** on an address suggests the class name from MSVC RTTI on that object. Structure travel / map work should name Structures with those RTTI strings, not manual `Type 2` / version suffixes (those are human dups). Catalog symbol `PlayerVariables` is **host+8** (offset origin), not necessarily an RTTI object — call `getRTTIClassName` on **host** / real instances / access-log `this` (often RCX).
