const functions = require("firebase-functions");
const axios = require("axios");
const cors = require("cors")({origin: true});

exports.blizzardProxy = functions.https.onRequest((request, response) => {
  cors(request, response, async () => {
    const blizzardApiUrl = request.query.url;
    if (!blizzardApiUrl) {
      response.status(400).send("URL-параметр не указан");
      return;
    }

    console.log(`Проксируем запрос на: ${blizzardApiUrl}`);
    console.log("Заголовки запроса:", request.headers);

    try {
      const apiResponse = await axios.get(blizzardApiUrl.toString(), {
        headers: {
          "Authorization": request.headers.authorization,
          "Accept": "application/json",
        },
      });

      console.log("Ответ от Blizzard получен, статус:", apiResponse.status);
      response.status(apiResponse.status).send(apiResponse.data);
    } catch (error) {
      console.error("Ошибка при проксировании запроса:", error.response ? error.response.data : error.message);
      if (error.response) {
        response.status(error.response.status).send(error.response.data);
      } else {
        response.status(500).send("Внутренняя ошибка сервера при обращении к прокси");
      }
    }
  });
});
