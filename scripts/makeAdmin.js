const admin = require('firebase-admin');
const serviceAccount = require('./serviceAccountKey.json'); // download from Firebase Console

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const uid = 'REPLACE_WITH_UID';

async function promote() {
  await admin.auth().setCustomUserClaims(uid, { admin: true });
  await admin.firestore().collection('users').doc(uid).set({ role: 'admin' }, { merge: true });
  console.log('Promoted to admin:', uid);
  process.exit(0);
}

promote().catch(err => { console.error(err); process.exit(1); });