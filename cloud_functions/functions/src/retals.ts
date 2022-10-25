import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { FactionModel, Attack, State } from "./interfaces/faction_interface";
import { sendNotificationToUser } from "./notification";
const rp = require("request-promise");

export const retalsGroup = {

    evaluateRetals: functions.region('us-east4').pubsub
        .schedule("*/2 * * * *")
        .onRun(async () => {
            const promises: Promise<any>[] = [];

            try {
                // Get factions that have at least one member signed-up for retals
                const firebaseAdmin = require("firebase-admin");
                const db = firebaseAdmin.database();
                const refFactions = db.ref("retals/factions");

                await refFactions.once("value", async function (snapshot) {
                    const factionsList = snapshot.val() || "";

                    let ownFactionId = 0;
                    // Get recent attacks for each faction
                    for (let id in factionsList) {

                        ownFactionId = +id;  // Parse to integer

                        let originalNoHostWarning = factionsList[id].noHostWarning;

                        // Placeholder in the db, skip
                        if (ownFactionId === 0) continue;

                        // DEBUG!
                        //if (ownFactionId !== 33241) continue;

                        if (factionsList[id].timestamp === undefined) {
                            await db.ref(`retals/factions/${ownFactionId}/api`).set("");
                        }

                        if (factionsList[id].api === undefined) {
                            await db.ref(`retals/factions/${ownFactionId}/timestamp`).set(0);
                        }

                        const currentDateInMillis = Math.floor(Date.now() / 1000);
                        const factionTimeUpdated = factionsList[id].timestamp;

                        let subscribers = [];

                        // Is any API key available?
                        let apiKey = factionsList[id].api ?? "";

                        if (apiKey === "") {
                            // There might not be anything on first execution

                            // Get all members subscribed from this faction and get the API key of the last active
                            // Later we can use this same subscribers if needed (if there are retals)
                            const response = await admin
                                .firestore()
                                .collection("players")
                                .where("active", "==", true)
                                .where("faction", "==", ownFactionId)  // Parsed id
                                .where("retalsNotification", "==", true)
                                .get();

                            subscribers = response.docs.map((d) => d.data());

                            // If there are no subscribers, get rid of this faction in the database
                            if (subscribers.length === 0) {
                                refFactions.child(ownFactionId).remove();
                                continue;
                            }

                            // If there are no hosts, send a notification
                            let numberOfHosts = 0;
                            for (const key of Array.from(subscribers.keys())) {
                                if (subscribers[key].retalsNotificationHost) {
                                    numberOfHosts++
                                }
                            }
                            if (numberOfHosts === 0 && !factionsList[id].noHostWarning) {
                                for (const key of Array.from(subscribers.keys())) {

                                    let title = "Retaliation notifications inactive";
                                    let body = "No users in this faction detected with faction API access permits " +
                                        "and retaliation notifications active in Torn PDA.\n\n" +
                                        "Retaliation notifications might not work!";
                                    if (subscribers[key].discrete) {
                                        title = `Retals`;
                                        body = `Inactive`;
                                    }

                                    promises.push(
                                        sendNotificationToUser(
                                            subscribers[key].token,
                                            title,
                                            body,
                                            "notification_retals",
                                            "#FF0000",
                                            "Alerts retals",
                                            "",
                                            "",
                                            "-1",
                                            "-1",
                                            subscribers[key].vibration,
                                            "sword_clash.aiff"
                                        )
                                    );
                                }
                                db.ref(`retals/factions/${ownFactionId}/noHostWarning`).set(true);
                                continue;
                            } else if (numberOfHosts > 0) {
                                // Rearm the no-hosts warning
                                db.ref(`retals/factions/${ownFactionId}/noHostWarning`).set(false);
                            }

                            // Update with the most recent updated subscriber
                            // (to ensure that the apiKey is valid)
                            let lastActiveUserTime = 0;
                            let lastActiveUserApiKey = "";

                            for (const key of Array.from(subscribers.keys())) {
                                // Only take into account hosts (users with faction API permits)
                                if (!subscribers[key].retalsNotificationHost) continue;

                                if (subscribers[key].lastActive > lastActiveUserTime) {
                                    lastActiveUserTime = subscribers[key].lastActive;
                                    lastActiveUserApiKey = subscribers[key].apiKey;
                                }
                            }

                            apiKey = lastActiveUserApiKey;
                            // Update the faction apiKey
                            db.ref(`retals/factions/${ownFactionId}/api`).set(lastActiveUserApiKey);
                        }

                        // Update the faction timestamp
                        db.ref(`retals/factions/${ownFactionId}/timestamp`).set(currentDateInMillis);

                        // Use api to get attacks information and see if we have new retals
                        const apiAttacks = await rp({
                            uri: `https://api.torn.com/faction/${ownFactionId}?selections=basic,attacks&key=${apiKey}`,
                            json: false,
                        });

                        // If permissions are not right, remove this user as a host
                        if (apiAttacks.includes("Incorrect ID-entity relation")) {
                            db.ref(`retals/factions/${ownFactionId}/api`).set("");

                            const response = await admin
                                .firestore()
                                .collection("players")
                                .where("apiKey", "==", apiKey)
                                .get();

                            subscribers = response.docs.map((d) => d.data());

                            for (const key of Array.from(subscribers.keys())) {
                                promises.push(
                                    admin
                                        .firestore()
                                        .collection("players")
                                        .doc(subscribers[key].uid)
                                        .update({
                                            retalsNotificationHost: false,
                                        })
                                );
                            }

                            // If we had already sent a no-host warning to the faction, and for some
                            // reason we encounter a username that lost his privileges after activating
                            // (still with host == true), leave the warning as it was to avoid sending another notification
                            if (originalNoHostWarning) {
                                db.ref(`retals/factions/${ownFactionId}/noHostWarning`).set(true);
                            }
                            continue;
                        }

                        // If the key is incorrect, deactivate the user and clean the key in the db
                        if (apiAttacks.includes("Incorrect key")) {
                            db.ref(`retals/factions/${ownFactionId}/api`).set("");

                            const response = await admin
                                .firestore()
                                .collection("players")
                                .where("apiKey", "==", apiKey)
                                .get();

                            subscribers = response.docs.map((d) => d.data());

                            for (const key of Array.from(subscribers.keys())) {
                                promises.push(
                                    admin
                                        .firestore()
                                        .collection("players")
                                        .doc(subscribers[key].uid)
                                        .update({
                                            active: false,
                                        })
                                );
                            }
                            continue;
                        }

                        const factionModel: FactionModel = JSON.parse(apiAttacks);

                        let notificationTitle = "";
                        let notificationBody = ""
                        let numberOrRetals = 0;
                        let lastRetalAttackerId = "";
                        let lastRetalName = "";
                        let lastRetalTargetId = 0;
                        let allRetalNames = [];
                        let allRetalNamesTrimmed = [];
                        let retalMinutesRemaining = 0;
                        let totalRetalsAbroad = 0;

                        // Get all susceptible attacks (5 minutes)
                        const lastFiveMinutes: Attack[] = [];

                        for (let attackId in factionModel.attacks) {
                            if (factionModel.attacks[attackId].attacker_name !== "" &&
                                currentDateInMillis - factionModel.attacks[attackId].timestamp_ended < 300 &&
                                factionModel.attacks[attackId].timestamp_ended > factionTimeUpdated
                            ) {
                                lastFiveMinutes.push(factionModel.attacks[attackId]);
                            }
                        }

                        for (let incomingId in lastFiveMinutes) {
                            // This is a valid incoming won attack in the last five minutes
                            if (lastFiveMinutes[incomingId].attacker_faction !== ownFactionId &&
                                lastFiveMinutes[incomingId].respect > 0) {

                                let alreadyRetaliated = false;
                                // Ensure that we have not retaliated already
                                for (let outgoingId in lastFiveMinutes) {
                                    if (lastFiveMinutes[outgoingId].timestamp_started > lastFiveMinutes[incomingId].timestamp_ended &&
                                        lastFiveMinutes[outgoingId].defender_name === lastFiveMinutes[incomingId].attacker_name &&
                                        lastFiveMinutes[outgoingId].respect > 0) {
                                        alreadyRetaliated = true;
                                    }
                                }
                                if (alreadyRetaliated) continue;

                                // Discard duplicated names (successive attacks)
                                if (allRetalNamesTrimmed.includes(lastFiveMinutes[incomingId].attacker_name)) {
                                    continue;
                                }

                                // If we reached here, it's a valid retal
                                numberOrRetals++;
                                lastRetalAttackerId = lastFiveMinutes[incomingId].attacker_id.toString();
                                lastRetalTargetId = lastFiveMinutes[incomingId].defender_id;
                                lastRetalName = lastFiveMinutes[incomingId].attacker_name;

                                if (lastFiveMinutes[incomingId].modifiers.overseas > 1) {
                                    totalRetalsAbroad++;
                                }

                                allRetalNamesTrimmed.push(lastRetalName);
                                if (allRetalNames.length === 0) {
                                    allRetalNames.push(lastRetalName);
                                } else {
                                    allRetalNames.push(` ${lastRetalName}`);
                                }
                                retalMinutesRemaining = Math.round((lastFiveMinutes[incomingId].timestamp_ended + 300 - currentDateInMillis) / 60);

                                // DEBUG
                                /*
                                functions.logger.warn(`Retal CODE: ${lastFiveMinutes[incomingId].code}`);
                                functions.logger.warn(`Retal time_stamp: ${lastFiveMinutes[incomingId].timestamp_ended}`);
                                functions.logger.warn(`CurrentDateInMillis: ${currentDateInMillis}`);
                                functions.logger.warn(`Minutes notified: ${retalMinutesRemaining}`);
                                console.log("________________");
                                console.log(`Code: ${lastFiveMinutes[incomingId].code}`);
                                console.log(`Retal number: ${numberOrRetals}`);
                                console.log(`Retal player id: ${lastRetalAttackerId}`);
                                console.log(`Retal player name: ${lastRetalName}`);
                                console.log(`Retal minutes: ${retalMinutesRemaining}`);
                                */
                            }
                        }

                        if (numberOrRetals === 0) continue;

                        if (numberOrRetals === 1) {
                            notificationTitle = `Retal on ${lastRetalName}`;
                            notificationBody = `Expires in ${retalMinutesRemaining} minutes`;
                        } else {
                            notificationTitle = `${numberOrRetals} retals active!`;
                            notificationBody = `${allRetalNames}`;
                        }

                        // If we didn't fill the subscribers before, do it now and also update the apiKey
                        if (subscribers.length === 0) {
                            const response = await admin
                                .firestore()
                                .collection("players")
                                .where("active", "==", true)
                                .where("faction", "==", ownFactionId)  // Parsed id
                                .where("retalsNotification", "==", true)
                                .get();

                            subscribers = response.docs.map((d) => d.data());

                            // If there are no subscribers, get rid of this faction in the database
                            if (subscribers.length === 0) {
                                refFactions.child(ownFactionId).remove();
                                continue;
                            }

                            // Update with the most recent updated subscriber
                            // (to ensure that the apiKey is valid)
                            let lastActiveUserTime = 0;
                            let lastActiveUserApiKey = "";

                            for (const key of Array.from(subscribers.keys())) {
                                if (subscribers[key].lastActive > lastActiveUserTime) {
                                    lastActiveUserTime = subscribers[key].lastActive;
                                    lastActiveUserApiKey = subscribers[key].apiKey;
                                }
                            }

                            // Update the faction apiKey
                            db.ref(`retals/factions/${ownFactionId}/api`).set(lastActiveUserApiKey);
                        }

                        for (const key of Array.from(subscribers.keys())) {
                            // DEBUG
                            /*
                            console.log(`############`);
                            console.log(`Notification title: ${notificationTitle}`);
                            console.log(`Notification body: ${notificationBody}`);
                            console.log(`Subscriber's ID: ${subscribers[key].playerId}`);
                            console.log(`Retal attacker's ID: ${lastRetalAttackerId}`);
                            console.log(`Retal target's ID: ${lastRetalTargetId}`);
                            console.log(`Retals abroad: ${totalRetalsAbroad}`);
                            */

                            if (numberOrRetals === 1 && subscribers[key].playerId === lastRetalTargetId) {
                                // Avoid notifying about own retaliations suffered by one self
                                // (limited to when there is only one retal to notify)
                                continue;
                            }

                            // Find out where our subscriber is
                            let subscriberState = "";
                            for (let memberId in factionModel.members) {
                                if (factionModel.members[memberId].name === subscribers[key].name) {
                                    subscriberState = factionModel.members[memberId].status.state.toString();
                                }
                            }

                            // CASES WHEN TRAVELING
                            // If subscriber is traveling, do not disturb
                            if (subscriberState === State.Traveling) {
                                continue;
                            }
                            // If he is in Torn and all retals are abroad, don't notify
                            else if (subscriberState === State.Okay) {
                                if (totalRetalsAbroad === numberOrRetals) {
                                    continue;
                                }
                            }
                            // If he is abroad and all retals took place in Torn, don't notify
                            else if (subscriberState === State.Abroad) {
                                if (totalRetalsAbroad === 0) {
                                    continue;
                                }
                            }

                            // DEBUG! 
                            //if (subscribers[key].name !== "Manuito") continue;

                            let title = notificationTitle;
                            let body = notificationBody;
                            if (subscribers[key].discrete) {
                                title = `Retal`;
                                body = ` `;
                            }

                            promises.push(
                                sendNotificationToUser(
                                    subscribers[key].token,
                                    title,
                                    body,
                                    "notification_retals",
                                    "#FF0000",
                                    "Alerts retals",
                                    "",
                                    "",
                                    lastRetalAttackerId,
                                    numberOrRetals.toString(),
                                    subscribers[key].vibration,
                                    "sword_clash.aiff"
                                )
                            );
                        }

                        functions.logger.info(`Retals faction ${ownFactionId}: ${subscribers.length} players`);
                    }
                });
            } catch (e) {
                functions.logger.warn(`ERROR RETALS\n${e}`);
            }

            await Promise.all(promises);
        }),
}