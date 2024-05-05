import urllib.request
import cv2
import io
import numpy as np
from deepface import DeepFace

class RecognitionCaffe:

    def __init__(self, img_url):
        self._img_url = img_url

    def get_image_stream(self):
        with urllib.request.urlopen(self._img_url) as url:
            stream = io.BytesIO(url.read())
        return stream

    def get_age_average(self, tuple):
        return (tuple[0] + tuple[1])/2

    def get_predicted_data(self):
        root = "./lib/face/People-tracking-with-Age-and-Gender-detection/"

        age_net = cv2.dnn.readNetFromCaffe(
            root + "age_gender_models/deploy_age.prototxt",
            root + "age_gender_models/age_net.caffemodel")
        gender_net = cv2.dnn.readNetFromCaffe(
            root + "age_gender_models/deploy_gender.prototxt",
            root + "age_gender_models/gender_net.caffemodel")

        MODEL_MEAN_VALUES = (78.4263377603, 87.7689143744, 114.895847746)
        age_list = [(0, 2), (4, 6), (8, 12), (15, 20), (25, 32), (38, 43), (48, 53), (60, 100)]
        gender_list = ['Male', 'Female']

        stream = self.get_image_stream()
        data = np.fromstring(stream.getvalue(), dtype=np.uint8)
        stream.close()

        img = cv2.imdecode(data, cv2.IMREAD_ANYCOLOR)

        blob2 = cv2.dnn.blobFromImage(img, 1, (227, 227), MODEL_MEAN_VALUES, swapRB=False)

        # Predict gender
        gender_net.setInput(blob2)
        gender_preds = gender_net.forward()
        gender = gender_list[gender_preds[0].argmax()]
        #print("gender = " + gender)
        # Predict age
        age_net.setInput(blob2)
        age_preds = age_net.forward()
        age = self.get_age_average(age_list[age_preds[0].argmax()])
        return {
            "age": age,
            "gender": gender.lower()
        }


def main():
    img_url = "https://storage.yandexcloud.net/instagram-parser/imgs/ca56688c04a900fee74dbb53b3e8d28c.jpg"
    data = DeepFace.analyze(img_path = img_url, actions = ['age', 'gender', 'race', 'emotion'])
    print(data)


if __name__ == "__main__":
    main()