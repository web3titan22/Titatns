// Registry.mo - Manages creators and tip jars
import HashMap "mo:base/HashMap";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Buffer "mo:base/Buffer";
import Types "Types";

actor class Registry() {
  type Creator = Types.Creator;
  type TipJar = Types.TipJar;
  type TipJarId = Types.TipJarId;
  type Error = Types.Error;
  type Result<T, E> = Types.Result<T, E>;

  // Stable storage for upgrades
  stable var creatorsEntries: [(Principal, Creator)] = [];
  stable var tipJarsEntries: [(TipJarId, TipJar)] = [];
  stable var usernamesEntries: [(Text, Principal)] = [];
  stable var tipJarCounter: Nat = 0;

  // Runtime state
  var creators = HashMap.HashMap<Principal, Creator>(10, Principal.equal, Principal.hash);
  var tipJars = HashMap.HashMap<TipJarId, TipJar>(10, Text.equal, Text.hash);
  var usernames = HashMap.HashMap<Text, Principal>(10, Text.equal, Text.hash);

  // ===== CREATOR MANAGEMENT =====

  public shared(msg) func registerCreator(req: Types.CreateCreatorRequest): async Result<Creator, Error> {
    let caller = msg.caller;
    
    // Check if already registered
    switch (creators.get(caller)) {
      case (?_) { return #err(#alreadyExists) };
      case null {};
    };

    // Check username availability
    let lowerUsername = Text.toLowercase(req.username);
    switch (usernames.get(lowerUsername)) {
      case (?_) { return #err(#invalidInput("Username taken")) };
      case null {};
    };

    // Validate username
    if (Text.size(req.username) < 3 or Text.size(req.username) > 20) {
      return #err(#invalidInput("Username must be 3-20 characters"));
    };

    let creator: Creator = {
      id = caller;
      username = req.username;
      displayName = req.displayName;
      bio = req.bio;
      avatarUrl = req.avatarUrl;
      createdAt = Time.now();
      totalReceived = 0;
      tipJarIds = [];
    };

    creators.put(caller, creator);
    usernames.put(lowerUsername, caller);
    
    #ok(creator)
  };

  public shared(msg) func updateCreator(req: Types.CreateCreatorRequest): async Result<Creator, Error> {
    let caller = msg.caller;
    
    switch (creators.get(caller)) {
      case null { #err(#notFound) };
      case (?existing) {
        let updated: Creator = {
          id = existing.id;
          username = existing.username; // Username cannot change
          displayName = req.displayName;
          bio = req.bio;
          avatarUrl = req.avatarUrl;
          createdAt = existing.createdAt;
          totalReceived = existing.totalReceived;
          tipJarIds = existing.tipJarIds;
        };
        creators.put(caller, updated);
        #ok(updated)
      };
    }
  };

  public query func getCreator(principal: Principal): async Result<Creator, Error> {
    switch (creators.get(principal)) {
      case null { #err(#notFound) };
      case (?c) { #ok(c) };
    }
  };

  public query func getCreatorByUsername(username: Text): async Result<Creator, Error> {
    let lowerUsername = Text.toLowercase(username);
    switch (usernames.get(lowerUsername)) {
      case null { #err(#notFound) };
      case (?principal) {
        switch (creators.get(principal)) {
          case null { #err(#notFound) };
          case (?c) { #ok(c) };
        }
      };
    }
  };

  // ===== TIP JAR MANAGEMENT =====

  public shared(msg) func createTipJar(req: Types.CreateTipJarRequest): async Result<TipJar, Error> {
    let caller = msg.caller;
    
    // Must be registered creator
    switch (creators.get(caller)) {
      case null { return #err(#unauthorized) };
      case (?creator) {
        tipJarCounter += 1;
        let jarId = "tj_" # Nat.toText(tipJarCounter);
        
        let tipJar: TipJar = {
          id = jarId;
          owner = caller;
          name = req.name;
          description = req.description;
          targetAmount = req.targetAmount;
          currentAmount = 0;
          suggestedAmounts = req.suggestedAmounts;
          thankYouMessage = req.thankYouMessage;
          isActive = true;
          createdAt = Time.now();
          widgetTheme = req.widgetTheme;
        };

        tipJars.put(jarId, tipJar);

        // Update creator's tip jar list
        let updatedJarIds = Array.append(creator.tipJarIds, [jarId]);
        let updatedCreator: Creator = {
          id = creator.id;
          username = creator.username;
          displayName = creator.displayName;
          bio = creator.bio;
          avatarUrl = creator.avatarUrl;
          createdAt = creator.createdAt;
          totalReceived = creator.totalReceived;
          tipJarIds = updatedJarIds;
        };
        creators.put(caller, updatedCreator);

        #ok(tipJar)
      };
    }
  };

  public shared(msg) func updateTipJar(jarId: TipJarId, req: Types.CreateTipJarRequest): async Result<TipJar, Error> {
    let caller = msg.caller;
    
    switch (tipJars.get(jarId)) {
      case null { #err(#notFound) };
      case (?jar) {
        if (jar.owner != caller) {
          return #err(#unauthorized);
        };
        
        let updated: TipJar = {
          id = jar.id;
          owner = jar.owner;
          name = req.name;
          description = req.description;
          targetAmount = req.targetAmount;
          currentAmount = jar.currentAmount;
          suggestedAmounts = req.suggestedAmounts;
          thankYouMessage = req.thankYouMessage;
          isActive = jar.isActive;
          createdAt = jar.createdAt;
          widgetTheme = req.widgetTheme;
        };
        tipJars.put(jarId, updated);
        #ok(updated)
      };
    }
  };

  public shared(msg) func toggleTipJar(jarId: TipJarId, active: Bool): async Result<TipJar, Error> {
    let caller = msg.caller;
    
    switch (tipJars.get(jarId)) {
      case null { #err(#notFound) };
      case (?jar) {
        if (jar.owner != caller) {
          return #err(#unauthorized);
        };
        
        let updated: TipJar = {
          id = jar.id;
          owner = jar.owner;
          name = jar.name;
          description = jar.description;
          targetAmount = jar.targetAmount;
          currentAmount = jar.currentAmount;
          suggestedAmounts = jar.suggestedAmounts;
          thankYouMessage = jar.thankYouMessage;
          isActive = active;
          createdAt = jar.createdAt;
          widgetTheme = jar.widgetTheme;
        };
        tipJars.put(jarId, updated);
        #ok(updated)
      };
    }
  };

  public query func getTipJar(jarId: TipJarId): async Result<TipJar, Error> {
    switch (tipJars.get(jarId)) {
      case null { #err(#notFound) };
      case (?j) { #ok(j) };
    }
  };

  public query func getCreatorTipJars(principal: Principal): async [TipJar] {
    switch (creators.get(principal)) {
      case null { [] };
      case (?creator) {
        let jars = Buffer.Buffer<TipJar>(creator.tipJarIds.size());
        for (jarId in creator.tipJarIds.vals()) {
          switch (tipJars.get(jarId)) {
            case (?jar) { jars.add(jar) };
            case null {};
          };
        };
        Buffer.toArray(jars)
      };
    }
  };

  // Called by Treasury canister after successful tip
  public shared(msg) func recordTipReceived(jarId: TipJarId, amount: Nat): async Result<(), Error> {
    // TODO: Add access control - only Treasury can call this
    
    switch (tipJars.get(jarId)) {
      case null { #err(#notFound) };
      case (?jar) {
        let updatedJar: TipJar = {
          id = jar.id;
          owner = jar.owner;
          name = jar.name;
          description = jar.description;
          targetAmount = jar.targetAmount;
          currentAmount = jar.currentAmount + amount;
          suggestedAmounts = jar.suggestedAmounts;
          thankYouMessage = jar.thankYouMessage;
          isActive = jar.isActive;
          createdAt = jar.createdAt;
          widgetTheme = jar.widgetTheme;
        };
        tipJars.put(jarId, updatedJar);

        // Update creator total
        switch (creators.get(jar.owner)) {
          case null {};
          case (?creator) {
            let updatedCreator: Creator = {
              id = creator.id;
              username = creator.username;
              displayName = creator.displayName;
              bio = creator.bio;
              avatarUrl = creator.avatarUrl;
              createdAt = creator.createdAt;
              totalReceived = creator.totalReceived + amount;
              tipJarIds = creator.tipJarIds;
            };
            creators.put(jar.owner, updatedCreator);
          };
        };

        #ok(())
      };
    }
  };

  // ===== STATS =====

  public query func getStats(): async { totalCreators: Nat; totalTipJars: Nat } {
    {
      totalCreators = creators.size();
      totalTipJars = tipJars.size();
    }
  };

  // ===== UPGRADE HOOKS =====

  system func preupgrade() {
    creatorsEntries := Iter.toArray(creators.entries());
    tipJarsEntries := Iter.toArray(tipJars.entries());
    usernamesEntries := Iter.toArray(usernames.entries());
  };

  system func postupgrade() {
    creators := HashMap.fromIter<Principal, Creator>(creatorsEntries.vals(), 10, Principal.equal, Principal.hash);
    tipJars := HashMap.fromIter<TipJarId, TipJar>(tipJarsEntries.vals(), 10, Text.equal, Text.hash);
    usernames := HashMap.fromIter<Text, Principal>(usernamesEntries.vals(), 10, Text.equal, Text.hash);
  };
}