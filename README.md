# RealmJS

RealmJS contains Realm bindings for integrating with mobile apps built using javascript frameworks such as ReactNative and PhoneGap.

## ReactNative Example
Make sure your environment is set up to run react native applications. Follow the instructions here https://facebook.github.io/react-native/docs/getting-started.html to the point you have installed the react-native-cli.

The ReactNative sample project is in the `examples/ReactExample` directory. You must run `npm install` in this directory before running the example for the first time.

## ReactNative Project Setup
- Create a new ReactNative project `react-native init <project-name>` and open the generated XCode project.
- Drag `RealmJS.xcodeproj` into the `Libraries` folder in your project.
- In the target for your application, add `libRealmReact.a` in the `Link Binary with Library` build phase.
- Use Realm in your app.

