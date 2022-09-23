import os, json, sequtils, strutils, uuids, times
import json_serialization, chronicles

import ../../../app/global/global_singleton
import ./dto/accounts as dto_accounts
import ./dto/generated_accounts as dto_generated_accounts
from ../keycard/service import KeycardEvent, KeyDetails 
import ../../../backend/general as status_general
import ../../../backend/core as status_core

import ../../../app/core/fleets/fleet_configuration
import ../../common/[account_constants, network_constants, utils, string_utils]
import ../../../constants as main_constants

export dto_accounts
export dto_generated_accounts


logScope:
  topics = "accounts-service"

const PATHS = @[PATH_WALLET_ROOT, PATH_EIP_1581, PATH_WHISPER, PATH_DEFAULT_WALLET]
const ACCOUNT_ALREADY_EXISTS_ERROR =  "account already exists"
const output_csv {.booldefine.} = false

include utils


type
  Service* = ref object of RootObj
    fleetConfiguration: FleetConfiguration
    generatedAccounts: seq[GeneratedAccountDto]
    accounts: seq[AccountDto]
    loggedInAccount: AccountDto
    importedAccount: GeneratedAccountDto
    isFirstTimeAccountLogin: bool
    keyStoreDir: string
    defaultWalletEmoji: string

proc delete*(self: Service) =
  discard

proc newService*(fleetConfiguration: FleetConfiguration): Service =
  result = Service()
  result.fleetConfiguration = fleetConfiguration
  result.isFirstTimeAccountLogin = false
  result.keyStoreDir = main_constants.ROOTKEYSTOREDIR
  result.defaultWalletEmoji = ""

proc getLoggedInAccount*(self: Service): AccountDto =
  return self.loggedInAccount

proc getImportedAccount*(self: Service): GeneratedAccountDto =
  return self.importedAccount

proc isFirstTimeAccountLogin*(self: Service): bool =
  return self.isFirstTimeAccountLogin

proc setKeyStoreDir(self: Service, key: string) = 
  self.keyStoreDir = joinPath(main_constants.ROOTKEYSTOREDIR, key) & main_constants.sep
  discard status_general.initKeystore(self.keyStoreDir)

proc setDefaultWalletEmoji*(self: Service, emoji: string) =
  self.defaultWalletEmoji = emoji

proc init*(self: Service) =
  try:
    let response = status_account.generateAddresses(PATHS)

    self.generatedAccounts = map(response.result.getElems(),
    proc(x: JsonNode): GeneratedAccountDto = toGeneratedAccountDto(x))

    for account in self.generatedAccounts.mitems:
      account.alias = generateAliasFromPk(account.derivedAccounts.whisper.publicKey)

  except Exception as e:
    error "error: ", procName="init", errName = e.name, errDesription = e.msg

proc clear*(self: Service) =
  self.generatedAccounts = @[]
  self.loggedInAccount = AccountDto()
  self.importedAccount = GeneratedAccountDto()
  self.isFirstTimeAccountLogin = false

proc validateMnemonic*(self: Service, mnemonic: string): string =
  try:
    let response = status_general.validateMnemonic(mnemonic)

    var error = "response doesn't contain \"error\""
    if(response.result.contains("error")):
      error = response.result["error"].getStr

    # An empty error means that mnemonic is valid.
    return error

  except Exception as e:
    error "error: ", procName="validateMnemonic", errName = e.name, errDesription = e.msg

proc generatedAccounts*(self: Service): seq[GeneratedAccountDto] =
  if(self.generatedAccounts.len == 0):
    error "There was some issue initiating account service"
    return

  result = self.generatedAccounts

proc openedAccounts*(self: Service): seq[AccountDto] =
  try:
    let response = status_account.openedAccounts(main_constants.STATUSGODIR)

    self.accounts = map(response.result.getElems(), proc(x: JsonNode): AccountDto = toAccountDto(x))

    return self.accounts

  except Exception as e:
    error "error: ", procName="openedAccounts", errName = e.name, errDesription = e.msg

proc storeDerivedAccounts(self: Service, accountId, hashedPassword: string,
  paths: seq[string]): DerivedAccounts =
  let response = status_account.storeDerivedAccounts(accountId, hashedPassword, paths)

  if response.result.contains("error"):
    raise newException(Exception, response.result["error"].getStr)

  result = toDerivedAccounts(response.result)

proc storeAccount(self: Service, accountId, hashedPassword: string): GeneratedAccountDto =
  let response = status_account.storeAccounts(accountId, hashedPassword)

  if response.result.contains("error"):
    raise newException(Exception, response.result["error"].getStr)

  result = toGeneratedAccountDto(response.result)

proc saveAccountAndLogin(self: Service, hashedPassword: string, account,
  subaccounts, settings, config: JsonNode): AccountDto =
  try:
    let response = status_account.saveAccountAndLogin(hashedPassword, account, subaccounts, settings, config)

    var error = "response doesn't contain \"error\""
    if(response.result.contains("error")):
      error = response.result["error"].getStr
      if error == "":
        debug "Account saved succesfully"
        self.isFirstTimeAccountLogin = true
        result = toAccountDto(account)
        return

    let err = "Error saving account and logging in: " & error
    error "error: ", procName="saveAccountAndLogin", errDesription = err

  except Exception as e:
    error "error: ", procName="saveAccountAndLogin", errName = e.name, errDesription = e.msg

proc saveKeycardAccountAndLogin(self: Service, chatKey, password: string, account, subaccounts, settings, 
  config: JsonNode): AccountDto =
  try:
    let response = status_account.saveAccountAndLoginWithKeycard(chatKey, password, account, subaccounts, settings, config)

    var error = "response doesn't contain \"error\""
    if(response.result.contains("error")):
      error = response.result["error"].getStr
      if error == "":
        debug "Account saved succesfully"
        result = toAccountDto(account)
        return

    let err = "Error saving account and logging in via keycard : " & error
    error "error: ", procName="saveKeycardAccountAndLogin", errDesription = err

  except Exception as e:
    error "error: ", procName="saveKeycardAccountAndLogin", errName = e.name, errDesription = e.msg

proc prepareAccountJsonObject(self: Service, account: GeneratedAccountDto, displayName: string): JsonNode =
  result = %* {
    "name": if displayName == "": account.alias else: displayName,
    "address": account.address,
    "key-uid": account.keyUid,
    "keycard-pairing": nil
  }

proc getAccountDataForAccountId(self: Service, accountId: string, displayName: string): JsonNode =
  for acc in self.generatedAccounts:
    if(acc.id == accountId):
      return self.prepareAccountJsonObject(acc, displayName)

  if(self.importedAccount.isValid()):
    if(self.importedAccount.id == accountId):
      return self.prepareAccountJsonObject(self.importedAccount, displayName)

proc prepareSubaccountJsonObject(self: Service, account: GeneratedAccountDto, displayName: string):
  JsonNode =
  result = %* [
    {
      "public-key": account.derivedAccounts.defaultWallet.publicKey,
      "address": account.derivedAccounts.defaultWallet.address,
      "color": "#4360df",
      "wallet": true,
      "path": PATH_DEFAULT_WALLET,
      "name": "Status account",
      "derived-from": account.address,
      "emoji": self.defaultWalletEmoji
    },
    {
      "public-key": account.derivedAccounts.whisper.publicKey,
      "address": account.derivedAccounts.whisper.address,
      "name": if displayName == "": account.alias else: displayName,
      "path": PATH_WHISPER,
      "chat": true,
      "derived-from": ""
    }
  ]

proc getSubaccountDataForAccountId(self: Service, accountId: string, displayName: string): JsonNode =
  for acc in self.generatedAccounts:
    if(acc.id == accountId):
      return self.prepareSubaccountJsonObject(acc, displayName)

  if(self.importedAccount.isValid()):
    if(self.importedAccount.id == accountId):
      return self.prepareSubaccountJsonObject(self.importedAccount, displayName)

proc prepareAccountSettingsJsonObject(self: Service, account: GeneratedAccountDto,
  installationId: string, displayName: string): JsonNode =
  result = %* {
    "key-uid": account.keyUid,
    "mnemonic": account.mnemonic,
    "public-key": account.derivedAccounts.whisper.publicKey,
    "name": account.alias,
    "display-name": displayName,
    "address": account.address,
    "eip1581-address": account.derivedAccounts.eip1581.address,
    "dapps-address": account.derivedAccounts.defaultWallet.address,
    "wallet-root-address": account.derivedAccounts.walletRoot.address,
    "preview-privacy?": true,
    "signing-phrase": generateSigningPhrase(3),
    "log-level": $LogLevel.INFO,
    "latest-derived-path": 0,
    "currency": "usd",
    "networks/networks": @[],
    "networks/current-network": "",
    "wallet/visible-tokens": {},
    "waku-enabled": true,
    "appearance": 0,
    "installation-id": installationId,
    "current-user-status": %* {
        "publicKey": account.derivedAccounts.whisper.publicKey,
        "statusType": 1,
        "clock": 0,
        "text": ""
      }
  }

proc getAccountSettings(self: Service, accountId: string,
  installationId: string,
  displayName: string): JsonNode =
  for acc in self.generatedAccounts:
    if(acc.id == accountId):
      return self.prepareAccountSettingsJsonObject(acc, installationId, displayName)

  if(self.importedAccount.isValid()):
    if(self.importedAccount.id == accountId):
      return self.prepareAccountSettingsJsonObject(self.importedAccount, installationId, displayName)

proc getDefaultNodeConfig*(self: Service, installationId: string): JsonNode =
  let fleet = Fleet.Prod

  result = NODE_CONFIG.copy()
  result["ClusterConfig"]["Fleet"] = newJString($fleet)
  result["ClusterConfig"]["BootNodes"] = %* self.fleetConfiguration.getNodes(fleet, FleetNodes.Bootnodes)
  result["ClusterConfig"]["TrustedMailServers"] = %* self.fleetConfiguration.getNodes(fleet, FleetNodes.Mailservers)
  result["ClusterConfig"]["StaticNodes"] = %* self.fleetConfiguration.getNodes(fleet, FleetNodes.Whisper)
  result["ClusterConfig"]["RendezvousNodes"] = %* self.fleetConfiguration.getNodes(fleet, FleetNodes.Rendezvous)
  result["ClusterConfig"]["DiscV5BootstrapNodes"] = %* (@[]) # TODO: set default status.prod enr
  result["NetworkId"] = NETWORKS[0]{"chainId"}
  result["DataDir"] = "ethereum".newJString()
  result["UpstreamConfig"]["Enabled"] = true.newJBool()
  result["UpstreamConfig"]["URL"] = NETWORKS[0]{"rpcUrl"}
  result["ShhextConfig"]["InstallationID"] = newJString(installationId)

  # TODO: fleet.status.im should have different sections depending on the node type
  #       or maybe it's not necessary because a node has the identify protocol
  result["ClusterConfig"]["RelayNodes"] =  %* self.fleetConfiguration.getNodes(fleet, FleetNodes.Waku)
  result["ClusterConfig"]["StoreNodes"] =  %* self.fleetConfiguration.getNodes(fleet, FleetNodes.Waku)
  result["ClusterConfig"]["FilterNodes"] =  %* self.fleetConfiguration.getNodes(fleet, FleetNodes.Waku)
  result["ClusterConfig"]["LightpushNodes"] =  %* self.fleetConfiguration.getNodes(fleet, FleetNodes.Waku)

  result["KeyStoreDir"] = newJString(self.keyStoreDir.replace(main_constants.STATUSGODIR, ""))

proc setLocalAccountSettingsFile(self: Service) =
  if(defined(macosx) and self.getLoggedInAccount.isValid()):
    singletonInstance.localAccountSettings.setFileName(self.getLoggedInAccount.name)

proc addKeycardDetails(self: Service, settingsJson: var JsonNode, accountData: var JsonNode) =
  let keycardPairingJsonString = readFile(main_constants.KEYCARDPAIRINGDATAFILE)
  let keycardPairingJsonObj = keycardPairingJsonString.parseJSON
  let now = now().toTime().toUnix()
  for instanceUid, kcDataObj in keycardPairingJsonObj:
    if not settingsJson.isNil:
      settingsJson["keycard-instance-uid"] = %* instanceUid
      settingsJson["keycard-paired-on"] = %* now
      settingsJson["keycard-pairing"] = kcDataObj{"key"}
    if not accountData.isNil:
      accountData["keycard-pairing"] = kcDataObj{"key"}

proc setupAccount*(self: Service, accountId, password, displayName: string, keycardUsage: bool): string =
  try:
    let installationId = $genUUID()
    var accountDataJson = self.getAccountDataForAccountId(accountId, displayName)

    var usedPassword = password
    if password.len == 0:
      # this means we're setting up an account using keycard
      usedPassword = accountDataJson{"key-uid"}.getStr

    self.setKeyStoreDir(accountDataJson{"key-uid"}.getStr)

    let subaccountDataJson = self.getSubaccountDataForAccountId(accountId, displayName)
    var settingsJson = self.getAccountSettings(accountId, installationId, displayName)
    let nodeConfigJson = self.getDefaultNodeConfig(installationId)

    if(accountDataJson.isNil or subaccountDataJson.isNil or settingsJson.isNil or
      nodeConfigJson.isNil):
      let description = "at least one json object is not prepared well"
      error "error: ", procName="setupAccount", errDesription = description
      return description

    let hashedPassword = hashString(usedPassword)
    discard self.storeAccount(accountId, hashedPassword)
    discard self.storeDerivedAccounts(accountId, hashedPassword, PATHS)

    if keycardUsage:
      self.addKeycardDetails(settingsJson, accountDataJson)
    
    self.loggedInAccount = self.saveAccountAndLogin(hashedPassword, accountDataJson,
      subaccountDataJson, settingsJson, nodeConfigJson)
    self.setLocalAccountSettingsFile()

    if self.getLoggedInAccount.isValid():
      return ""
    else:
      return "logged in account is not valid"
  except Exception as e:
    error "error: ", procName="setupAccount", errName = e.name, errDesription = e.msg
    return e.msg

proc setupAccountKeycard*(self: Service, keycardData: KeycardEvent) = 
  try:
    let installationId = $genUUID()

    let alias = generateAliasFromPk(keycardData.whisperKey.publicKey)
    
    let openedAccounts = self.openedAccounts()
    var displayName: string
    for acc in openedAccounts:
      if acc.keyUid == keycardData.keyUid:
        displayName = acc.name
        break
    if displayName.len == 0:
      displayName = self.getLoggedInAccount().name

    var accountDataJson = %* {
      "name": alias,
      "display-name": displayName,
      "address": keycardData.masterKey.address,
      "key-uid": keycardData.keyUid
    }

    self.setKeyStoreDir(keycardData.keyUid)
    let nodeConfigJson = self.getDefaultNodeConfig(installationId)
    let subaccountDataJson = %* [
      {
        "public-key": keycardData.walletKey.publicKey,
        "address": keycardData.walletKey.address,
        "color": "#4360df",
        "wallet": true,
        "path": PATH_DEFAULT_WALLET,
        "name": "Status account",
        "derived-from": keycardData.masterKey.address,
        "emoji": self.defaultWalletEmoji,
      },
      {
        "public-key": keycardData.whisperKey.publicKey,
        "address": keycardData.whisperKey.address,
        "name": alias,
        "path": PATH_WHISPER,
        "chat": true,
        "derived-from": ""
      }
    ]

    var settingsJson = %* {
      "key-uid": keycardData.keyUid,
      "public-key": keycardData.whisperKey.publicKey,
      "name": alias,
      "display-name": "",
      "address":  keycardData.whisperKey.address,
      "eip1581-address":  keycardData.eip1581Key.address,
      "dapps-address":  keycardData.walletKey.address,
      "wallet-root-address":  keycardData.walletRootKey.address,
      "preview-privacy?": true,
      "signing-phrase": generateSigningPhrase(3),
      "log-level": $LogLevel.INFO,
      "latest-derived-path": 0,
      "currency": "usd",
      "networks/networks": @[],
      "networks/current-network": "",
      "wallet/visible-tokens": {},
      "waku-enabled": true,
      "appearance": 0,
      "installation-id": installationId,
      "current-user-status": {
        "publicKey": keycardData.whisperKey.publicKey,
        "statusType": 1,
        "clock": 0,
        "text": ""
      }
    }

    self.addKeycardDetails(settingsJson, accountDataJson)
    
    if(accountDataJson.isNil or subaccountDataJson.isNil or settingsJson.isNil or
      nodeConfigJson.isNil):
      let description = "at least one json object is not prepared well"
      error "error: ", procName="setupAccountKeycard", errDesription = description
      return

    let hashedPassword = hashString(keycardData.keyUid) # using hashed keyUid as password

    self.loggedInAccount = self.saveKeycardAccountAndLogin(keycardData.whisperKey.privateKey, 
      hashedPassword, 
      accountDataJson, 
      subaccountDataJson, 
      settingsJson, 
      nodeConfigJson)
  except Exception as e:
    error "error: ", procName="setupAccount", errName = e.name, errDesription = e.msg

proc createAccountFromMnemonic*(self: Service, mnemonic: string): GeneratedAccountDto =
  if mnemonic.len == 0:
    error "empty mnemonic"
    return
  try:
    let response = status_account.createAccountFromMnemonic(mnemonic)
    return toGeneratedAccountDto(response.result)
  except Exception as e:
    error "error: ", procName="createAccountFromMnemonic", errName = e.name, errDesription = e.msg

proc importMnemonic*(self: Service, mnemonic: string): string =
  if mnemonic.len == 0:
    return "empty mnemonic"
  try:
    let response = status_account.multiAccountImportMnemonic(mnemonic)
    self.importedAccount = toGeneratedAccountDto(response.result)

    if (self.accounts.contains(self.importedAccount.keyUid)):
      return ACCOUNT_ALREADY_EXISTS_ERROR

    let responseDerived = status_account.deriveAccounts(self.importedAccount.id, PATHS)
    self.importedAccount.derivedAccounts = toDerivedAccounts(responseDerived.result)

    self.importedAccount.alias= generateAliasFromPk(self.importedAccount.derivedAccounts.whisper.publicKey)

    if (not self.importedAccount.isValid()):
      return "imported account is not valid"
  except Exception as e:
    error "error: ", procName="importMnemonic", errName = e.name, errDesription = e.msg
    return e.msg

proc login*(self: Service, account: AccountDto, password: string): string =
  try:
    let hashedPassword = hashString(password)
    var thumbnailImage: string
    var largeImage: string
    for img in account.images:
      if(img.imgType == "thumbnail"):
        thumbnailImage = img.uri
      elif(img.imgType == "large"):
        largeImage = img.uri

    let keyStoreDir = joinPath(main_constants.ROOTKEYSTOREDIR, account.keyUid) & main_constants.sep
    if not dirExists(keyStoreDir):
      os.createDir(keyStoreDir)
      status_core.migrateKeyStoreDir($ %* {
        "key-uid": account.keyUid
      }, password, main_constants.ROOTKEYSTOREDIR, keyStoreDir)

    self.setKeyStoreDir(account.keyUid)
    # This is moved from `status-lib` here
    # TODO:
    # If you added a new value in the nodeconfig in status-go, old accounts will not have this value, since the node config
    # is stored in the database, and it's not easy to migrate using .sql
    # While this is fixed, you can add here any missing attribute on the node config, and it will be merged with whatever
    # the account has in the db
    var nodeCfg = %* {
      "KeyStoreDir": self.keyStoreDir.replace(main_constants.STATUSGODIR, ""),
      "ShhextConfig": %* {
        "BandwidthStatsEnabled": true
      },
      "Web3ProviderConfig": %* {
        "Enabled": true
      },
      "EnsConfig": %* {
        "Enabled": true
      },
      "WalletConfig": {
        "Enabled": true,
        "OpenseaAPIKey": OPENSEA_API_KEY_RESOLVED
      },
      "TorrentConfig": {
        "Enabled": false,
        "DataDir": DEFAULT_TORRENT_CONFIG_DATADIR,
        "TorrentDir": DEFAULT_TORRENT_CONFIG_TORRENTDIR,
        "Port": DEFAULT_TORRENT_CONFIG_PORT
      },
      "Networks": NETWORKS,
      "OutputMessageCSVEnabled": output_csv
    }

    # Source the connection port from the environment for debugging or if default port not accessible
    if existsEnv("STATUS_PORT"):
      nodeCfg["ListenAddr"] = newJString("0.0.0.0:" & $getEnv("STATUS_PORT"))

    let response = status_account.login(account.name, account.keyUid, hashedPassword, thumbnailImage,
      largeImage, $nodeCfg)
    var error = "response doesn't contain \"error\""
    if(response.result.contains("error")):
      error = response.result["error"].getStr
      if error == "":
        debug "Account logged in"
        self.loggedInAccount = account
        self.setLocalAccountSettingsFile()

    return error

  except Exception as e:
    error "error: ", procName="login", errName = e.name, errDesription = e.msg
    return e.msg

proc loginAccountKeycard*(self: Service, keycardData: KeycardEvent): string = 
  try:
    self.setKeyStoreDir(keycardData.keyUid)

    let openedAccounts = self.openedAccounts()
    var accToBeLoggedIn: AccountDto
    for acc in openedAccounts:
      if acc.keyUid == keycardData.keyUid:
        accToBeLoggedIn = acc
        break

    var accountDataJson = %* {
      "name": accToBeLoggedIn.name,
      "address": keycardData.masterKey.address,
      "key-uid": keycardData.keyUid
    }
    var settingsJson: JsonNode
    self.addKeycardDetails(settingsJson, accountDataJson)

    let hashedPassword = hashString(keycardData.keyUid) # using hashed keyUid as password

    let response = status_account.loginWithKeycard(keycardData.whisperKey.privateKey, 
      hashedPassword,
      accountDataJson)

    var error = "response doesn't contain \"error\""
    if(response.result.contains("error")):
      error = response.result["error"].getStr
      if error == "":
        debug "Account logged in succesfully"
        # this should be fetched later from waku
        self.loggedInAccount = accToBeLoggedIn
        self.loggedInAccount.keycardPairing = accountDataJson{"keycard-pairing"}.getStr
        return
  except Exception as e:
    error "error: ", procName="loginAccountKeycard", errName = e.name, errDesription = e.msg
    return e.msg

proc verifyAccountPassword*(self: Service, account: string, password: string): bool =
  try:
    let response = status_account.verifyAccountPassword(account, password, self.keyStoreDir)
    if(response.result.contains("error")):
      let errMsg = response.result["error"].getStr
      if(errMsg.len == 0):
        return true
      else:
        error "error: ", procName="verifyAccountPassword", errDesription = errMsg
    return false
  except Exception as e:
    error "error: ", procName="verifyAccountPassword", errName = e.name, errDesription = e.msg


proc convertToKeycardAccount*(self: Service, keyUid: string, password: string): bool = 
  try:
    var accountDataJson = %* {
      "name": self.getLoggedInAccount().name,
      "key-uid": keyUid
    }
    var settingsJson = %* {
      "display-name": self.getLoggedInAccount().name
    }

    self.addKeycardDetails(settingsJson, accountDataJson)
    
    if(accountDataJson.isNil or settingsJson.isNil):
      let description = "at least one json object is not prepared well"
      error "error: ", procName="convertToKeycardAccount", errDesription = description
      return

    let hashedCurrentPassword = hashString(password)
    let hashedNewPassword = hashString(keyUid)

    let response = status_account.convertToKeycardAccount(self.keyStoreDir, accountDataJson, settingsJson, hashedCurrentPassword, 
    hashedNewPassword)

    if(response.result.contains("error")):
      let errMsg = response.result["error"].getStr
      if(errMsg.len == 0):
        return true
      else:
        error "error: ", procName="convertToKeycardAccount", errDesription = errMsg
    return false
  except Exception as e:
    error "error: ", procName="convertToKeycardAccount", errName = e.name, errDesription = e.msg

proc verifyPassword*(self: Service, password: string): bool =
  try:
    let hashedPassword = hashString(password)
    let response = status_account.verifyPassword(hashedPassword)
    return response.result.getBool
  except Exception as e:
    error "error: ", procName="verifyPassword", errName = e.name, errDesription = e.msg
  return false