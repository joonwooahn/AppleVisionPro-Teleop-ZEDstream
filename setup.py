from setuptools import setup, find_packages

setup(
    name='avp_stream',
    version='1.0',
    description='This python package streams diverse tracking data available from AVP to any devices that can communicate with gRPC. Also streams ZED camera stream over TCP.',
    author='Younghyo Park, Joonwoo Ahn',
    author_email='younghyo@mit.edu, joonwooahn@snu.ac.kr',
    packages=find_packages(),
    install_requires=[
        'numpy', 'grpcio', 'grpcio-tools', 'matplotlib'
    ],
    extras_require={
    },
)