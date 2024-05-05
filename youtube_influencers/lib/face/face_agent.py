import argparse
from email.mime import image
import json
from json.decoder import JSONDecodeError
from math import ceil
from deepface import DeepFace
import logging
import os
import sys
import pika
import time
import yaml
from pika.exceptions import AMQPError, ChannelError, ReentrancyError, \
    StreamLostError, AMQPHeartbeatTimeout, ConnectionClosedByBroker, ChannelWrongStateError, ConnectionClosed, \
    ConnectionBlockedTimeout

from RecognitionCaffe import RecognitionCaffe
from RecognitionYoloKeras import RecognitionYoloKeras

RABBITMQ_CONFIG = {"host": "localhost"}
LOGGER = logging.getLogger(__name__)
LOGGING_FORMAT_STRING = (
    "${asctime}|${levelname}|${name}|PID ${process}|TID ${thread}|${message}"
)

LOG_LEVEL_MAP = {
    "critical": logging.CRITICAL,
    "fatal": logging.CRITICAL,
    "error": logging.ERROR,
    "warning": logging.WARNING,
    "warn": logging.WARNING,
    "info": logging.INFO,
    "debug": logging.DEBUG
}


class Configuration:
    def __init__(self, raw_config):
        self._config = raw_config

    @property
    def rabbitmq(self):
        return self._config["rmq"]

    @property
    def infrastructure(self):
        return self._config["infrastructure"]

    @property
    def settings(self):
        return self._config["settings"]


class FaceDataPublisher:
    def __init__(self, config, to_exchange):
        self._config = config
        self._cnx = None
        self._channel = None
        self._to_exchange = to_exchange

        self._reset_channel()

    def _reset_channel(self):
        self.close()
        self._cnx = _create_rabbitmq_connection(self._config)
        self._channel = self._cnx.channel()

    def close(self):
        if self._channel is not None and self._channel.is_open:
            self._channel.close()
        if self._cnx is not None and self._cnx.is_open:
            self._cnx.close()

    def publish_message(self, payload):
        try:
            self._publish(payload)
        except (StreamLostError, ConnectionClosedByBroker, ChannelWrongStateError, ConnectionClosed,
                ConnectionBlockedTimeout):
            LOGGER.info(
                "Publishing channel is closed. Reopening connection and channel..."
            )

            self._reset_channel()
            self._publish(payload)

    def _publish(self, payload):
        body = json.dumps(payload)  # , default=default_serialize
        self._channel.basic_publish(
            exchange=self._to_exchange,
            routing_key="",
            body=body,
            properties=pika.BasicProperties(
                delivery_mode=2,  # make message persistent
            ),
        )


class FaceAgent:
    def __init__(self, configuration: Configuration):
        self._configuration = configuration

        self._connection = None
        self._channel = None
        self._from_queue = self._configuration.infrastructure["face_queue"]
        self._to_exchange = self._configuration.infrastructure["export_exchange"]

        self._publisher = FaceDataPublisher(configuration.rabbitmq, self._to_exchange)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, trace):
        self._publisher.close()

    def _init_connection_and_channel(self):
        self._connection = _create_rabbitmq_connection(self._configuration.rabbitmq)
        self._channel = self._connection.channel()

    def _close_connection_and_channel(self):
        if self._channel is not None and self._channel.is_open:
            self._channel.stop_consuming()
            self._channel.close()

        if self._connection is not None and self._connection.is_open:
            self._connection.close()

    def run_forever(self):
        self._close_connection_and_channel()
        self._init_connection_and_channel()
        channel = self._channel

        # Allowing fair dispatch for all workers
        channel.basic_qos(prefetch_count=1)

        channel.basic_consume(
            queue=self._from_queue,
            on_message_callback=self._on_message_received_callback,
        )

        LOGGER.info("Service is ready to consume incoming messages")

        try:
            channel.start_consuming()
        except (
                AMQPHeartbeatTimeout, StreamLostError, ConnectionClosedByBroker, ChannelWrongStateError,
                ConnectionClosed,
                ConnectionBlockedTimeout):
            LOGGER.warning(
                "Channel start_consuming connection lost error", exc_info=True
            )
            time.sleep(60 * 2)
            LOGGER.info("Trying reconnect after connection fail.")
            self.run_forever()

    def _on_message_received_callback(self, channel, method, properties, body):
        # Message confirmation details: https://www.rabbitmq.com/confirms.html

        LOGGER.debug("New price message received: %s", body)

        try:
            self._try_process_new_message_body(body)

        except (JSONDecodeError, TypeError, ValueError):
            LOGGER.error(
                "Invalid JSON '%s' obtained from the input queue", body, exc_info=True
            )
            channel.basic_nack(delivery_tag=method.delivery_tag, requeue=False)

        except (AMQPError, ChannelError, ReentrancyError):
            LOGGER.error(
                "Error during sending a message '%s' to output queue",
                body,
                exc_info=True,
            )
            channel.basic_nack(delivery_tag=method.delivery_tag, requeue=False)

        else:
            channel.basic_ack(delivery_tag=method.delivery_tag)

            LOGGER.debug("Message '%s' is processed successfully", body)

    def _try_process_new_message_body(self, body):
        message = json.loads(body)
        youtube_userid = message['youtube_userid']
        img_url = message['profile_pic_url_hd']
#         try:
#             data = DeepFace.analyze(img_path = img_url, actions = ['age', 'gender', 'race'])
#             age = int(data['age'])
#             gender = data['gender']
# 
#             if gender == 'Man':
#                 gender = 'male'
#             else:
#                 gender = 'female'
#             ethnicity = data['dominant_race']
#             LOGGER.info("Success detect face with DeepFace")
#             self._send_message_to_output_queue(instgr_id, age, gender, ethnicity)
#             return
#         except Exception as e:
#             LOGGER.error("failed to detect face with DeepFace " + img_url)
#             LOGGER.error(str(e))
# 
#         try:
#             predictor_yolo = RecognitionYoloKeras(img_url)
#             predictor_yolo_data = predictor_yolo.get_predicted_data()
#             if predictor_yolo_data is not None and predictor_yolo_data['gender'] is not None and predictor_yolo_data['age'] is not None:
#                 LOGGER.info("Success detect face with RecognitionYoloKeras")
#                 self._send_message_to_output_queue(instgr_id, ceil(int(predictor_yolo_data['age'])), predictor_yolo_data['gender'], None)
#                 return
#             
#         except Exception as e:
#             LOGGER.error("failed to detect face with RecognitionYoloKeras")
#             LOGGER.error(str(e))

        try:
            predictor_caffe = RecognitionCaffe(img_url)
            predictor_caffe_data = predictor_caffe.get_predicted_data()
            if predictor_caffe_data is not None and predictor_caffe_data['gender'] is not None and predictor_caffe_data['age'] is not None:
                LOGGER.info("Success detect face with RecognitionCaffe")
                self._send_message_to_output_queue(youtube_userid, ceil(int(predictor_caffe_data['age'])), predictor_caffe_data['gender'], None)

        except Exception as e:
            LOGGER.error("failed to detect face with RecognitionCaffe")
            LOGGER.error(str(e))


    def _send_message_to_output_queue(self, id, age, gender, ethnicity):
        data = {
            'youtube_userid': id,
            'Age': age,
            'Gender': gender,
            'Ethnicity': ethnicity
        }

        export_msg = {
            'data': data,
            'type': 'face_recognition'
        }

        self._publisher.publish_message(export_msg)
        LOGGER.debug("Notification for the message '%s' was successully sent", export_msg)


def _set_log_level(loglevel):
    try:
        LOGGER.setLevel(LOG_LEVEL_MAP[loglevel])
    except:
        LOGGER.setLevel(logging.WARNING)
    finally:
        logging.basicConfig(style="$", format=LOGGING_FORMAT_STRING)


def _create_rabbitmq_connection(config):
    config_copy = {**config}
    config_copy['virtual_host'] = config_copy['vhost']

    crd = {
        'username': config['username'],
        'password': config['password'],
    }

    credentials = pika.PlainCredentials(**crd)
    config_copy.pop("username")
    config_copy.pop("password")
    config_copy.pop("vhost")

    return pika.BlockingConnection(
        pika.ConnectionParameters(credentials=credentials, **config_copy)
    )


def read_parameters_from_cli_arguments():
    parser = argparse.ArgumentParser(description="face recognition agent CLI")
    parser.add_argument(
        "-c",
        "--config",
        help="path to configuration file",
        required=True,
        dest="configuration_filename",
    )
    parser.add_argument(
        "-l",
        "--loglevel",
        help="log level",
        required=True,
        dest="log_level",
    )

    return parser.parse_args()


def read_configuration_from_file(filename: str) -> Configuration:
    with open(filename, 'r') as f:
        valuesYaml = yaml.load(f, Loader=yaml.FullLoader)

    return Configuration(valuesYaml)


def exit(status_code: int):
    # Borrowed from here: https://www.rabbitmq.com/tutorials/tutorial-one-python.html
    try:
        sys.exit(status_code)
    except SystemExit:
        os._exit(status_code)


def start_service(configuration: Configuration):
    with FaceAgent(configuration) as service:
        service.run_forever()


def main():
    cli_parameters = read_parameters_from_cli_arguments()
    configuration_filename = cli_parameters.configuration_filename
    _set_log_level(cli_parameters.log_level)

    LOGGER.info("Reading configuration from file '%s'", configuration_filename)
    try:
        configuration = read_configuration_from_file(configuration_filename)
    except:
        LOGGER.critical(
            "Something went wrong with reading configuration file '%s'",
            configuration_filename,
            exc_info=True,
        )
        exit(1)

    LOGGER.info("Starting service...")
    try:
        start_service(configuration)
    except KeyboardInterrupt:
        LOGGER.warning("Interrupted by user")
        exit(0)
    except:
        LOGGER.critical("Unhandled exception has happened", exc_info=True)
        exit(1)


if __name__ == "__main__":
    main()
