> **DevOps pipeline (EVAT-Chameleon) 7.3HD:** see [DEVOPS.md](DEVOPS.md) for the 7-stage Jenkins pipeline, setup steps, and security findings.


# EVAT-Mobile/App
- Company: Chameleon
- Project: EV Adoption Tools
- Team: Mobile/App

## Tech Stack
- NodeJS
- TypeScript
- Express.js
- MongoDB
- JWT

## Env Variables

Create a .env file in then root and add the following

```
PORT = 8080
MONGODB_URI = mongodb://<<address>>:<<port>>/EVAT
JWT_SECRET = 'abc123'
GOOGLE_MAPS_API_KEY=ABCD1234
GOOGLE_AI_API_KEY=ABCD1234
GOOGLE_APPLICATION_CREDENTIALS="C:\Path\To\Auth.json"
EMAIL_USER = "sender@example.com"
EMAIL_PASS = "See Nodemailer section"
ADMIN_EMAIL = "reciever@example.com"
```

### Authentication
#### Google Maps
1. Go to https://console.cloud.google.com/ and create a new project.
2. Ensure you have a billing account and it is enabled https://console.cloud.google.com/billing/
3. Click the sidebar menu and go to 'API & Services'
4. Click 'Enable APIs and services'
5. Search for and enable 'Places API (New)', 'Places API', 'Distance Matrix API', and 'Directions API'
6. At the top of the page search for 'Credentials' and click on it
7. Click 'Create Credentials' then 'API key'
8. Copy the API key into the `.env` file for `GOOGLE_MAPS_API_KEY="Key"`
9. Click 'Close' then 'Create Credentials', then 'Service account'
10. Give the service account a name and click 'Continue'
11. Select 'Role' then 'Basic' then 'Viewer'
12. Click 'Done'
13. Click on the service account email address you just created.
14. Click 'Keys' then 'Add key', 'Create new key', 'JSON', and then 'Create'
15. A JSON file will be downloaded to your computer. Move it to the the folder of the cloned Git repository and place it in a new /auth/ folder.
15. Copy the path of the file and place it in `.env` under `GOOGLE_APPLICATION_CREDENTIALS="Path/To/File.json`

### MongoDB
MongoDB is required to run the backend server. There are multiple ways to do this.

1. Locally using docker to download and run a MongoDB container.

https://www.docker.com/

https://hub.docker.com/_/mongo 

2. Download and install mongoDB locally on your computer - Use the MongoDB Community Server download.

https://www.mongodb.com/try/download/community-kubernetes-operator 

3. Create a free DB online using MongoDB Atlas (Links below)

https://www.mongodb.com/lp/cloud/atlas/try4-reg

https://www.mongodb.com/resources/basics/databases/free 

#### Ensure MongoDB has the correct data and schema for chargers
https://gist.github.com/EscWasTaken/3f08797d7470237ae3c2ed0dd149aace

#### MongoDB Compass 
A great tool for connecting, testing, editing, exporting and importing data into mongo databases.

https://www.mongodb.com/products/tools/compass 

### Nodemailer
[Nodemailer](https://nodemailer.com/) is the package used by EVAT-BE for sending admin email 2FA codes. At time of writing, it is setup to work with Gmail sending to a fixed sender address.

It will send from `EMAIL_USER` in the `.env` file to `ADMIN_EMAIL`, also in the `.env` file. These emails should be different to prevent issues with sending.

It may make more sense to send 2FA codes to the email of the admin user in the database, however this has not been implemented. If this were to be implemented it would also be beneficial to implement admin password hashing similar to how it is done for users, as the admin feature was developed independently.

To setup your Gmail account for Nodemailer, [follow these instructions](https://nodemailer.com/usage/using-gmail), and use the 'App Password' and place it into the `EMAIL_PASS` variable in the `.env` file.
This should be a 16 character string such as 'abcd efgh ijkl mnop'.

## Install Dependencies

```bash
npm install
```

## Run App

```bash
npm run server
```

## Test App
Testing of the app is done using [Jest](https://jestjs.io/).
Ensure you have run `npm install` before anything else.

All tests are to be located in the `/test` folder and separated by their files folder. An example of this is if we are writing tests for the `/src/controllers/user-controller.ts` file then the equivalent test file would be `/test/conrollers/user-controller.ts`. Some exceptions can be made for folders that only contain one piece of code such as `/src/config/database-config.ts` and `/src/utils/generate-token.ts` which can be placed in the `/test` folder.

Tests are to be written with the [AAA pattern](https://medium.com/@pjbgf/title-testing-code-ocd-and-the-aaa-pattern-df453975ab80) (Arrange, Act, Assert).

It is prefered to use nested [`describe()`](https://jestjs.io/docs/api#describename-fn) functions where the main `describe()` distinguishes the file being tested, and the nested `describe()` distinguishes the function being tested.

Tests are written using [`test(Case: Description of what should happen)`](https://jestjs.io/docs/api#testname-fn-timeout) rather than using `it(Should do this)` for clarity reasons.

To run the tests simply run
```bash
npm run test
```
and monitor the console for the test results.

For more in depth test debugging and running it is recommended to use the [Jest Test Explorer](https://marketplace.visualstudio.com/items?itemName=kavod-io.vscode-jest-test-adapter) VSCode extention or similar.

# MORE INFORMATION REQUIRED

## Fixes Required

1. Invalid token error occurring when performing GET /api/vehicle
Bearer is correct when checking in code.